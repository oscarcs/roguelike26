Don't create new branches or pull requests unless explicitly instructed to. Just push directly to the main branch when requested to commit and push.

Run the actual game to verify changes to the UI:
- This project uses `vaxis` and expects a real TTY. A plain non-interactive `zig build run` can fail trying to open `/dev/tty`.
- In Codex, run the game in a PTY-backed session. Use `exec_command` with `tty: true` for `zig build run`, then poll with `write_stdin`.
- The game can be inspected from that PTY output stream, and input can be sent the same way.
- Use `q` or `Ctrl-C` to exit the running game session.
- Use a terminal resolution of approx 188x57 as that is what it looks like on my screen