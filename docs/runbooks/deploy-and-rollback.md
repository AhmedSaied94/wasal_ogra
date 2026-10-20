# Deploy and roll back

Deploys are automatic:

- A merge to `master` deploys **staging**, on the staging VM.
- A `vX.Y.Z` tag on a `master` commit deploys **production**, on the prod VM.

Each goes through `/opt/wassal/bin/deploy` on its own VM, over that VM's WireGuard. In order, it
validates the request, takes a per-environment lock, pulls the image, migrates, restarts, verifies,
and restores the previous release if anything after the migration fails. Each VM deploys only its
own environment, whoever asks. The full contract:
`specs/002-b01-backend-skeleton/contracts/operations.md` "Deploy interface"; background: research
R10.

## How a release reaches each environment

| | Staging | Production |
| --- | --- | --- |
| Trigger | A push to `master` that changed the backend (job `deploy-staging` in `backend.yml`) | Push a tag `vX.Y.Z` on a `master` commit (`backend-release.yml`) |
| Image | `ghcr.io/ahmedsaied94/wassal-backend:sha-<commit>`, built and pushed by that run | The same image, re-tagged `vX.Y.Z`, only if `sha-<commit>` exists. It exists only when the commit's `master` run passed every check. |
| GitHub Environment | `staging` | `production` |
| VM reached | The staging VM, as `deploy@10.67.0.1`, through its peer `deploy-staging` | The prod VM, as `deploy@10.66.0.1`, through its peer `deploy-prod` |
| Request sent | `staging sha-<commit>` | `prod vX.Y.Z` |

Two merges close together deploy one after the other: GitHub's job concurrency and the VM's lock
both serialize them. GitHub keeps one waiting run per group, so a third merge replaces the waiting
one, and the newest commit wins.

To release production:

```bash
git checkout master && git pull
git tag v0.1.0 && git push origin v0.1.0
```

A tag on a commit that isn't on `master`, or whose `master` run failed, stops at the `verify` job and
deploys nothing.

## Reading a failed deploy

The deploy job's log shows the VM script's output, and its exit code says what happened:

| Exit | Meaning | What's serving | Do |
| --- | --- | --- | --- |
| 2 | Bad request: an environment other than the VM's own (`this host serves <env>, not <other>`, from its `/etc/wassal/host.env`), a missing or broken `host.env`, a malformed tag, or a rehearsal sent to prod | Unchanged | Fix the workflow or the tag. If the environment is wrong, check that the GitHub Environment's secrets came from its own VM (provision-host.md step 8). |
| 3 | Another deploy of that environment held the lock for 15 min | Unchanged | Look for a stuck manual deploy on that VM (`ps aux \| grep deploy`), then re-run |
| 4 | The pull or the stack copy out of the image failed, or the release's stack definition was refused (`stack: …` lines) | Unchanged | For a pull, check that the GHCR package is public and the tag exists, then re-run. For `stack:` lines, the release's `docker/compose.yml` asks for more than the VM allows (contracts/operations.md, Deploy): fix it in a new commit. |
| 5 | The migration failed | **The previous release**; nothing was restarted | Fix the migration in a new commit. Read the error in the log. |
| 6 | The new release didn't become ready, or reported the wrong release, within 120 s | **The previous release**, restored | Read the container logs (below), fix, and deploy again |
| 7 | The restore failed too | Possibly nothing | **Act now.** Over that VM's WireGuard: `sudo docker compose -p wassal-<env> ps`, then the logs. Deploy a known-good tag by hand (Rollback). For production, the uptime alert is firing. |

On the environment's VM, over its WireGuard (`ssh ubuntu@10.66.0.1` for prod, `ssh ubuntu@10.67.0.1`
for staging):

```bash
cat /var/lib/wassal/<env>/release /var/lib/wassal/<env>/release.previous   # serving and previous tags
sudo docker compose -p wassal-<env> ps
sudo docker logs --tail 100 wassal-<env>-api-1
```

## Roll back

A rollback is an ordinary deploy of an older tag. **Migrations are never reversed**: every migration
must keep the previous release working (expand/contract), so the older code runs on the newer
schema.

- **From GitHub:** in Actions → `backend-release`, open the run for the tag you want, then choose
  **Re-run all jobs**. Production serves it again within about 10 minutes.
- **From the prod VM**, over its WireGuard as `ubuntu@10.66.0.1`:

  ```bash
  sudo env SSH_ORIGINAL_COMMAND='prod v1.2.2' /opt/wassal/bin/deploy --only prod
  ```

- **Staging**, from the staging VM over its WireGuard as `ubuntu@10.67.0.1`:

  ```bash
  sudo env SSH_ORIGINAL_COMMAND='staging sha-<commit>' /opt/wassal/bin/deploy --only staging
  ```

Each VM refuses the other environment (exit 2, `this host serves …, not …`), even with `sudo`.
Deploying the tag that is already serving changes nothing. It only re-checks `/readyz` and the
release on both ports.

## Rehearse the failure paths

These run the real failure and restore code against staging's containers, on the staging VM,
without a broken image. In Actions → `backend` → **Run workflow**, choose branch `master` and set
`rehearse` to one of:

| `rehearse` | Expect |
| --- | --- |
| `migrate-fail` | The deploy fails with exit 5. Staging keeps serving its release, and GitHub emails the failure. |
| `verify-fail` | The new containers start and fail verification, then the previous release is restored and the deploy exits 6 |

The job uses the newest `master` commit that has an image. Poll production during both runs. It
runs on the other VM, so it must answer `200` throughout (quickstart scenarios 11 and 12):

```bash
while sleep 1; do curl -s -o /dev/null -w '%{http_code}\n' https://api.193-122-74-125.sslip.io/healthz; done
```

## Images in GHCR

Every image stays in `ghcr.io/ahmedsaied94/wassal-backend`. Nothing deletes them today, and the
public package's storage is free (research R12). Two things rely on old images:

- **The monthly restore drill.** On the staging VM, it checks production's newest backup with the
  image of the production release that took it, pulled by its `sha-<commit>` tag (restore.md
  "Reading drill-results.jsonl"). Weekly backups are kept 56 days. So the `sha-` image of every
  commit production has run must stay for **at least 56 days** after production stopped running
  it. Without it, the drill fails.
- **Rollbacks.** Re-running an old tag's release workflow checks and re-tags its `sha-<commit>`
  image, and the VM pulls the `vX.Y.Z` tag.

If a registry cleanup is ever added (a cleanup workflow, or a package retention setting), it must
keep these. The safe rule: never delete a `sha-` image whose commit has a `v*` tag, or that `v*`
tag, until 56 days after the next release replaced it in production, and keep both for as long as
you might roll back to that release. Staging-only `sha-` images can go once staging no longer
serves them.

## One-time setup

Do these before the first merge (tasks T061 and T105).

1. **GitHub Environments** (Settings → Environments). Their secrets reach a VM, so a workflow
   edited on another branch must not be able to read them:
   - `staging`: under **Deployment branches and tags**, choose "Selected branches and tags" and add
     the branch rule `master`.
   - `production`: the same, with the tag rule `v*` only.
   - Recommended: add yourself as a required reviewer on `production`. Every release then waits for
     a click, so a bad commit on `master` can't reach production on its own (security review).
   - Under Settings → Branches, protect `master`: require a pull request and the `backend` and
     `gitleaks` checks.
2. **Deploy keys and peers:** follow provision-host.md step 8 on each VM. Each VM gets one
   WireGuard peer and one forced-command SSH key, for its own environment, and its GitHub
   Environment gets the three secrets `WG_CONFIG`, `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS`:

   | VM | Peer and key | Environment | `WG_CONFIG` | Host key pinned for |
   | --- | --- | --- | --- | --- |
   | staging | `deploy-staging`, `--only staging` | `staging` | `Endpoint = 141.147.129.92:51820`, `AllowedIPs = 10.67.0.1/32` | `10.67.0.1` |
   | prod | `deploy-prod`, `--only prod` | `production` | `Endpoint = 193.122.74.125:51820`, `AllowedIPs = 10.66.0.1/32` | `10.66.0.1` |

3. **Make the image public.** GHCR creates the package as private on the first `master` push, and
   the VMs pull without credentials. Under your GitHub profile → Packages → `wassal-backend` →
   Package settings, change the visibility to **Public**. The image holds no secrets (research R12).
   Until you do, deploys fail with exit 4.
4. **Failure emails:** under GitHub → Settings → Notifications → Actions, turn on email for failed
   workflows. That email is the deploy alert (FR-038).

### Replacing a deploy key

On the environment's own VM, over its WireGuard:

1. Remove the old key's line from `~deploy/.ssh/authorized_keys`.
2. Run `sudo wg-peer remove deploy-<env>`.
3. Repeat provision-host.md step 8 on that VM, and replace the three secrets in its GitHub
   Environment. The other VM and Environment are unaffected.

## Updating the edge or the host scripts

The edge (`backend/docker/edge/`) and the host scripts (`backend/docker/host/`) are not deployed by
CI. After a change merges, copy them to each VM and re-run the provisioning script there, the
staging VM first. Check that staging still serves before you do the prod VM.

- It installs the scripts and reloads Caddy.
- It re-applies the firewall only if the rules changed. Applying restarts Docker, and with it every
  container on that VM.
- It also installs pending package updates, and an update of Docker restarts the containers too. Run
  it in a quiet hour.
- If a run stops partway, run it again. It still applies rules it rendered but didn't load.

```bash
rsync -a --delete backend/docker/ ubuntu@10.67.0.1:wassal-docker/
ssh ubuntu@10.67.0.1 sudo ./wassal-docker/host/provision.sh

rsync -a --delete backend/docker/ ubuntu@10.66.0.1:wassal-docker/
ssh ubuntu@10.66.0.1 sudo ./wassal-docker/host/provision.sh
```

Run them from the repository root, over each VM's WireGuard. (`scp -r` into an existing
`wassal-docker` directory would nest the copy one level down.) Later runs don't need `--env`: each
VM reads its environment from `/etc/wassal/host.env`.

### The packs directory and the `/packs/` route (B04)

From B04 on, each VM's worker writes pack files to `/var/lib/wassal/packs`, and its edge serves them
under `https://<api-host>/packs/` (contracts/pack-delivery.md "Public files"). Before the first
release that includes B04 reaches a VM:

1. **Update the edge and re-run the provisioning script** there, as above. It creates
   `/var/lib/wassal/packs` (owner `10001:10001`, mode `0755`) and reloads Caddy with the `/packs/`
   route. Do this first: if the release starts before the directory exists, Docker creates it as
   `root`, and the worker refuses to start because it can't write there.
2. **Add the `CONTENT_*` values** to `/etc/wassal/<env>.env` (contracts/environment.md and
   owner-actions.md). Without them the app refuses to start.
3. **Deploy the release.** Then check the route:

```bash
curl -sI https://staging-api.<host>/packs/core.floor.json   # staging: 404, it has no floor file
curl -s https://api.<host>/packs/core.floor.json            # prod: {"max_version":0,"pack_id":"core"}
curl -s https://api.<host>/v1/content/manifest              # {"version":0,"packs":[]} before any promotion
```

Publishing and promoting are in [content-publishing.md](content-publishing.md).
