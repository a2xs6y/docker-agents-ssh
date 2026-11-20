# Coding agents over SSH in Docker

Run [Pi](https://pi.dev/), [Codex CLI](https://github.com/openai/codex), or [Google Antigravity CLI](https://antigravity.google/docs/getting-started?tab=cli) in Docker with an HTTP proxy backed by an SSH tunnel. Docker Compose starts the same gateway for each agent. The gateway supports a direct SSH connection or an optional jump host.

```text
Agent and its tools → gateway → SSH tunnel → exit server → internet
```

Each agent receives proxy environment variables from Compose. Privoxy forwards HTTP and HTTPS requests to an OpenSSH SOCKS listener, which sends destination hostnames through the tunnel for resolution by the SSH exit server. Agents join only an isolated Docker network. The gateway alone joins a second network for its SSH connection. All services drop all Linux capabilities, and the proxy port is internal to Docker.

## Requirements

- Linux with Docker Engine 28 or later and Docker Compose v2. The stack uses Docker's isolated bridge mode.
- An SSH exit server that permits TCP forwarding and can reach the services your agents use. The gateway health check also requires HTTPS access to `example.com` through the tunnel.
- An SSH identity for unattended authentication and verified host keys. The gateway UID must be able to read those files.

Programs that honor the proxy variables can reach external services. Direct TCP, UDP, IPv6 and external DNS queries from the agents have no internet route. Image builds use Docker's build network. The gateway may resolve the first SSH hop before opening the tunnel.

## Quick start

1. Create the local configuration and data directories.

   ```sh
   cp .env.example .env
   mkdir -p data/projects
   mkdir -m 700 -p data/.pi data/.codex data/.antigravity
   ```

2. Set `SSH_HOST` and `SSH_USER` in `.env`. The default SSH port is 22. Set `PI_UID` and `PI_GID` to the output of `id -u` and `id -g` so the agents can write files with your host ownership. The gateway uses the same numeric IDs by default. Set `GATEWAY_UID` and `GATEWAY_GID` if your SSH files use another owner. Both UIDs must be nonzero.

3. Place your private key in `config/id_ed25519` and verified host keys in `config/known_hosts`, or set `SSH_KEY_PATH` and `SSH_KNOWN_HOSTS_PATH` to your local paths. For a nonstandard port, use the `[host]:port` form in `known_hosts`.

   To use a jump host, set `SSH_JUMP_HOST` and add its verified host key to `known_hosts`. The jump host uses port 22 and inherits the exit server's username and key by default. Set `SSH_JUMP_PORT`, `SSH_JUMP_USER`, or `SSH_JUMP_KEY_PATH` as needed.

4. Build and start Pi. On first use, configure your model provider from inside Pi.

   ```sh
   docker compose build gateway pi
   docker compose run --rm pi
   ```

### Codex and Antigravity

Build the images and use the corresponding Compose service name.

```sh
docker compose build gateway codex antigravity
docker compose run --rm codex login --device-auth
docker compose run --rm codex
docker compose run --rm antigravity
```

Codex device sign-in requires device code authentication to be enabled for your ChatGPT account. To use a Gemini API key in Antigravity, set `"modelProvider": "gemini"` in `data/.antigravity/.gemini/antigravity-cli/settings.json` and pass an exported key with `docker compose run --rm -e GEMINI_API_KEY antigravity`. [Antigravity authentication](https://antigravity.google/docs/install?tab=cli)

To work in a specific project, place it under `data/projects` and select its directory at launch.

```sh
docker compose run --rm -w /data/projects/my-project pi
```

The same `-w` option works with `codex` and `antigravity`.

### Host shell aliases

Add these aliases to `~/.bashrc` or `~/.zshrc`, replacing the example path with your checkout. Open a new shell to run any of the agents from any directory.

```sh
alias pi-docker='docker compose --project-directory "$HOME/path/to/docker-agents-ssh" run --rm pi'
alias codex-docker='docker compose --project-directory "$HOME/path/to/docker-agents-ssh" run --rm codex'
alias agy-docker='docker compose --project-directory "$HOME/path/to/docker-agents-ssh" run --rm antigravity'
```

## Update the agents

From the repository directory, rebuild the images to install the latest CLI versions. `--pull` checks for a newer base image, and `--no-cache` reruns the installation steps.

```sh
docker compose build --pull --no-cache pi codex antigravity
```

To update only one agent, specify its service name, for example `docker compose build --pull --no-cache codex`. You can reuse the existing gateway image.

The next launch uses the rebuilt image. Open sessions continue on their current images until they exit. Settings and projects remain in `data/`.

### Remove old agent images

Before updating, list this project's image names and record the IDs of the agent images you plan to rebuild. Run these commands from the same directory and with the same Compose options you use to build:

```sh
docker compose config --images
docker image inspect --format '{{.Id}}' docker-agents-ssh-codex
```

Use the image name printed for the agent you are updating. The example assumes a checkout named `docker-agents-ssh` and the default Compose project name. After rebuilding, inspect that name again. If the ID changed, close any sessions still using the old image and check that the old ID has no tags:

```sh
docker image inspect --format '{{json .RepoTags}}' OLD_IMAGE_ID
```

If the output is `[]` or `null`, remove only the recorded old image with `docker image rm --no-prune OLD_IMAGE_ID`. If it still has tags or Docker reports that a container uses it, leave it in place. Repeat for each updated agent whose old ID you recorded. Settings and projects stay in `data/`. This procedure leaves the shared build cache alone.

## Proxy variables

Compose sets `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `ftp_proxy` and `FTP_PROXY` to `http://gateway:5187/`. It sets `rsync_proxy` and `RSYNC_PROXY` to `gateway:5187` in rsync's host-and-port format. Whether FTP or rsync works depends on the client and protocol. The default `no_proxy` and `NO_PROXY` cover loopback only. Use `PI_NO_PROXY` to set exceptions for all agents, for example `localhost,127.0.0.1,::1,localaddress,.example.test`. An exception bypasses the proxy but still needs a route on the isolated network.

## Persistent data

| Host path | Contents |
| --- | --- |
| `./data/projects/` | Project files and repositories |
| `./data/.pi/` | Pi settings, credentials, extensions, and sessions |
| `./data/.codex/` | Codex home and `CODEX_HOME`, including `config.toml` and sessions |
| `./data/.antigravity/` | Antigravity home, including `.gemini/antigravity-cli/settings.json` |

All three agents start in `/data/projects` and can run concurrently. They share project files, so concurrent edits to the same file can conflict. Pi runs with `HOME=/data` and mounts all of `./data`, including the other agents' settings directories. Codex and Antigravity each mount their own home directory and the shared projects directory. SSH keys and `known_hosts` are mounted only into the gateway. Git and the Docker build context each allow only explicitly listed project files. Keep secrets out of those files, and keep local configuration under the default ignored paths or outside the checkout. To move the setup to another machine, transfer `data/`, `.env`, and the SSH files separately from the Git checkout.

## Verify the route

Check HTTPS and remote hostname resolution through the proxy. The response should show the exit server's public IP.

```sh
docker compose run --rm --entrypoint curl pi --fail --show-error https://api.ipify.org
```

A direct connection by IP should fail even while the gateway is running.

```sh
docker compose run --rm --entrypoint curl pi --noproxy '*' --max-time 5 https://1.1.1.1/
```

To test loss of connectivity, keep a Pi shell open and stop the gateway from a second terminal.

```sh
# First terminal
docker compose run --rm --entrypoint sh pi

# Second terminal
docker compose stop gateway
```

Back in the Pi shell, `curl --max-time 5 https://example.com/` should fail. Start a fresh Pi session to bring the gateway back up. Use `docker compose logs gateway` to diagnose tunnel startup and `docker compose down` to stop the stack while keeping local data.
