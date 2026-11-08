import copy
from types import SimpleNamespace

import httpx
import pytest

from afterimage_levelgen.planning import make_plan
from afterimage_levelgen.providers import ProviderError, describe_album, generate_music


def client_with(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_async_submission_resume_and_wav(album, audio_path):
    requests = []
    snapshots = []
    state = {}

    def handler(request):
        requests.append(request)
        if request.method == "POST":
            assert b'"output_format"' in request.content and b"wav" in request.content
            assert b"stable-audio-3" in request.content
            return httpx.Response(202, json={"id": "job123"})
        return httpx.Response(200, content=audio_path.read_bytes())

    with client_with(handler) as client:
        result = generate_music(make_plan(album, 120, "electronic"), 42, "secret", state,
                                lambda s: snapshots.append(copy.deepcopy(s)), client=client)
    assert result == audio_path.read_bytes()
    assert snapshots[0]["status"] == "submitting"
    assert snapshots[1]["id"] == "job123"
    assert len(requests) == 2
    requests.clear()
    with client_with(handler) as client:
        generate_music(make_plan(album, 120, "electronic"), 42, "secret", state,
                       lambda s: None, client=client)
    assert [r.method for r in requests] == ["GET"]


@pytest.mark.parametrize("status", [400, 401, 402, 403, 429, 500])
def test_stability_errors_are_sanitized(album, status):
    calls = []
    def handler(request):
        calls.append(request)
        return httpx.Response(status, text="secret API key and private data")
    with client_with(handler) as client, pytest.raises(ProviderError) as exc:
        generate_music(make_plan(album, 120, "electronic"), 42, "secret", {}, lambda s: None, client=client)
    assert str(status) in str(exc.value)
    assert "secret" not in str(exc.value)
    assert len(calls) == 1


def test_submission_timeout_never_retries(album):
    calls = []
    state = {}
    def handler(request):
        calls.append(request)
        raise httpx.ReadTimeout("secret", request=request)
    with client_with(handler) as client:
        for _ in range(2):
            with pytest.raises(ProviderError):
                generate_music(make_plan(album, 120, "electronic"), 42, "secret", state, lambda s: None, client=client)
    assert len(calls) == 1
    assert state["status"] == "ambiguous"


@pytest.mark.parametrize("response", [httpx.Response(200, content=b"not audio"),
                                      httpx.Response(404), httpx.Response(429)])
def test_poll_failures_preserve_id(album, response):
    state = {"status": "polling", "id": "existing"}
    with client_with(lambda request: response) as client, pytest.raises(ProviderError):
        generate_music(make_plan(album, 120, "electronic"), 42, "secret", state, lambda s: None, client=client)
    assert state["id"] == "existing"


def test_poll_wait_and_timeout_resume(album, audio_path):
    replies = iter([httpx.Response(202), httpx.Response(200, content=audio_path.read_bytes())])
    waits = []
    with client_with(lambda request: next(replies)) as client:
        generate_music(make_plan(album, 120, "electronic"), 42, "secret", {"id": "saved"}, lambda s: None,
                       client=client, sleep=waits.append, progress=lambda s: None)
    assert waits == [10]


def test_missing_job_id_blocks_resubmission(album):
    state = {}
    with client_with(lambda r: httpx.Response(202, json={})) as client:
        with pytest.raises(ProviderError, match="no valid job ID"):
            generate_music(make_plan(album, 120, "electronic"), 42, "secret", state, lambda s: None, client=client)
    assert state["status"] == "submitting"


def test_gemini_structured_profile(album):
    class Models:
        def generate_content(self, **kwargs):
            assert kwargs["config"]["response_schema"].__name__ == "AlbumProfile"
            assert len(kwargs["contents"]) == 5
            return SimpleNamespace(text=album.model_dump_json())
    result = describe_album([("a.jpg", b"a"), ("b.jpg", b"b")], "trip", "model", "key",
                            client=SimpleNamespace(models=Models()))
    assert result == album


@pytest.mark.parametrize("payload", ["bad json", "{}", '{"summary":"x","photos":[]}'])
def test_gemini_malformed(payload):
    models = SimpleNamespace(generate_content=lambda **kw: SimpleNamespace(text=payload))
    with pytest.raises(ProviderError, match="valid album"):
        describe_album([("a.jpg", b"a")], "", "model", "key", client=SimpleNamespace(models=models))


@pytest.mark.parametrize("code", [401, 429, None])
def test_gemini_service_failure(code):
    class Failure(Exception):
        pass
    def fail(**kwargs):
        error = Failure("private provider data")
        error.code = code
        raise error
    with pytest.raises(ProviderError) as exc:
        describe_album([("a", b"a")], "", "model", "key",
                       client=SimpleNamespace(models=SimpleNamespace(generate_content=fail)))
    assert "private" not in str(exc.value)


def test_gemini_rejects_missing_photo_ids(album):
    models = SimpleNamespace(generate_content=lambda **kw: SimpleNamespace(text=album.model_dump_json()))
    with pytest.raises(ProviderError, match="valid album"):
        describe_album([("a", b"a")], "", "model", "key", client=SimpleNamespace(models=models))


def test_poll_network_failure_keeps_job(album):
    calls = []
    def fail(request):
        calls.append(request.method)
        raise httpx.ReadTimeout("timeout", request=request)
    state = {"id": "known", "status": "polling"}
    with client_with(fail) as client, pytest.raises(ProviderError, match="resume"):
        generate_music(make_plan(album, 120, "electronic"), 42, "secret", state, lambda s: None, client=client)
    assert calls == ["GET"] and state["id"] == "known"
