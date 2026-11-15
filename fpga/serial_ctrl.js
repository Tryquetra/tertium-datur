#!/usr/bin/env bun
import { execSync } from "node:child_process";
import fs from "node:fs";

const port = process.argv[2] || "/dev/ttyUSB1";
const commands = process.argv.slice(3);

if (commands.length === 0) {
  console.log("Usage: bun fpga/serial_ctrl.js <port=/dev/ttyUSB1> <cmd1> [cmd2 ...]");
  console.log("Commands: ? (status), c/+ (cw), a/- (ccw), i (invert), r/0 (reset), m (mode), d<int> (plot [-1093..1093])");
  process.exit(0);
}

if (!fs.existsSync(port)) {
  console.error(`Serial device not found: ${port}`);
  process.exit(1);
}

execSync(`stty -F ${port} 115200 raw -echo -echoe -echok -onlcr -icrnl`);

for (const cmd of commands) {
  const payload = (cmd[0] === "d" || cmd[0] === "D") && !cmd.endsWith("\n") ? `${cmd}\n` : cmd;
  const res = execSync(
    `python3 -c '
import os, select, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
while select.select([fd], [], [], 0.01)[0]:
    if not os.read(fd, 1024): break
os.write(fd, sys.argv[2].encode())
out = b""
for _ in range(20):
    r, _, _ = select.select([fd], [], [], 0.05)
    if not r:
        if b"\\n" in out: break
        continue
    chunk = os.read(fd, 256)
    if not chunk: break
    out += chunk
    if b"\\n" in out: break
os.close(fd)
sys.stdout.write(out.decode(errors="replace").strip())
' "${port}" "${payload}"`,
    { encoding: "utf8" }
  ).trim();
  console.log(`> ${cmd} -> ${res}`);
}
