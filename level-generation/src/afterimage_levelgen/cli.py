import argparse
import os
import sys
from pathlib import Path

from pydantic import ValidationError

from . import pipeline
from .providers import ProviderError


def parser():
    root = argparse.ArgumentParser(description="Create AFTERIMAGE levels from photos or audio")
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("generate", "chart", "rechart"):
        command = commands.add_parser(name)
        command.add_argument("--output", type=Path, required=True)
        command.add_argument("--title")
        command.add_argument("--seed", type=int, default=42)
        command.add_argument("--chart-seed", type=int, help="Vary patterns without regenerating music")
        command.add_argument("--device", choices=("cpu", "cuda"), default="cpu")
        if name == "generate":
            command.add_argument("--photos", type=Path, required=True)
            command.add_argument("--description", default="")
            command.add_argument("--duration", type=float, help="Override album-derived duration (10-240 seconds)")
            command.add_argument("--style", help="Override the photo-inspired musical style")
            command.add_argument("--gemini-model", default=os.environ.get("GEMINI_MODEL", "gemini-3.8-flash"))
        elif name == "chart":
            command.add_argument("--audio", type=Path, required=True)
    commands.add_parser("validate").add_argument("level", type=Path)
    return root


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    # Keep downloaded model weights and JIT caches in the ignored project cache.
    cache = Path(__file__).resolve().parents[2] / ".cache"
    os.environ.setdefault("TORCH_HOME", str(cache / "torch"))
    os.environ.setdefault("NUMBA_CACHE_DIR", str(cache / "numba"))
    try:
        if args.command == "validate":
            result = pipeline.validate(args.level)
            print(f"Valid: {result.title}, {len(result.notes)} notes")
        else:
            if not 1 <= args.seed <= 4294967294:
                raise ValueError("--seed must be between 1 and 4294967294 (provider seed 0 is random)")
            if args.command == "generate":
                if args.duration is not None and not 10 <= args.duration <= 240:
                    raise ValueError("--duration must be between 10 and 240 seconds")
                if len(args.style or "") > 300 or len(args.description) > 4000:
                    raise ValueError("Limit style to 300 characters and description to 4000")
                pipeline.generate(args, progress=lambda message: print(message, flush=True))
            elif args.command == "rechart":
                pipeline.rechart(args, progress=lambda message: print(message, flush=True))
            else:
                pipeline.chart(args, progress=lambda message: print(message, flush=True))
        return 0
    except ValidationError as exc:
        locations = ", ".join(".".join(map(str, e["loc"])) for e in exc.errors(include_input=False))
        print(f"Invalid data at: {locations}", file=sys.stderr)
    except (ValueError, OSError, ProviderError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
    except ImportError as exc:
        print(f"Missing dependency {exc.name}; install the pinned dependencies in the project venv", file=sys.stderr)
    except KeyboardInterrupt:
        print("Interrupted; rerun with the same output to resume completed stages.", file=sys.stderr)
        return 130
    return 1
