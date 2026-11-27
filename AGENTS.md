# OpenHyperAI agent instructions

- For architecture, generated sources and patch changes, start with [CLAUDE.md](CLAUDE.md) and [the architecture guide](docs/ARCHITECTURE.md).
- For client Bot tests, follow [the validation procedure](docs/BOT_MATCH_VALIDATION.md) and [the match recording standard](docs/BOT_MATCH_RECORDING.md).
- Before starting, capture the client patch/build, Bot script versions, exact code commit and any local overrides. After **every** match, even a loss or an aborted test, add or complete its report and the [match index](docs/BOT_MATCH_INDEX.md) before starting another test or handing off. If the replay is missing, log a pending or incomplete result and update the same entry later. Do not count incomplete runs as wins or losses.
- Keep observations and suspected causes separate. Compare to the last comparable match and the best known comparable run. Keep script changes separate from documentation and never treat a documentation commit as the version that played.
