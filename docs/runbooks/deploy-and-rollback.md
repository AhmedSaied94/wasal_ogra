# Deploy and roll back

Deploys are automatic:

- A merge to `master` deploys **staging**.
- A `vX.Y.Z` tag on a `master` commit deploys **production**.

Both go through `/opt/wassal/bin/deploy` on the host, over WireGuard. In order, it validates the
request, takes a per-environment lock, pulls the image, migrates, restarts, verifies, and restores the
previous release if anything after the migration fails. The full contract:
`specs/002-b01-backend-skeleton/contracts/operations.md` "Deploy interface"; background: research
R10.

## How a release reaches each environment

| | Staging | Production |
| --- | --- | --- |
| Trigger | A push to `master` that changed the backend (job `deploy-staging` in `backend.yml`) | Push a tag `vX.Y.Z` on a `master` commit (`backend-release.yml`) |
| Image | `ghcr.io/ahmedsaied94/wassal-backend:sha-<commit>`, built and pushed by that run | The same image, re-tagged `vX.Y.Z`, only if `sha-<commit>` exists. It exists only when the commit's `master` run passed every check. |
| Request sent | `staging sha-<commit>` | `prod vX.Y.Z` |

Two merges close together deploy one after the other: GitHub's job concurrency and the host lock both
serialize them. GitHub keeps one waiting run per group, so a third merge replaces the waiting one, and
the newest commit wins.

To release production:

```bash
git checkout master && git pull
git tag v0.1.0 && git push origin v0.1.0
```

A tag on a commit that isn't on `master`, or whose `master` run failed, stops at the `verify` job and
deploys nothing.

## Reading a failed deploy

The deploy job's log shows the host script's output, and its exit code says what happened:

| Exit | Meaning | What's serving | Do |
| --- | --- | --- | --- |
| 2 | Bad request: wrong environment for the key, a malformed tag, or a rehearsal sent to prod | Unchanged | Fix the workflow or the tag |
| 3 | Another deploy of that environment held the lock for 15 min | Unchanged | Look for a stuck manual deploy (`ps aux \| grep deploy`), then re-run |
| 4 | The pull or the stack copy out of the image failed, or the release's stack definition was refused (`stack: …` lines) | Unchanged | For a pull, check that the GHCR package is public and the tag exists, then re-run. For `stack:` lines, the release's `docker/compose.yml` asks for more than the host allows (contracts/operations.md, Deploy): fix it in a new commit. |
| 5 | The migration failed | **The previous release**; nothing was restarted | Fix the migration in a new commit. Read the error in the log. |
| 6 | The new release didn't become ready, or reported the wrong release, within 120 s | **The previous release**, restored | Read the container logs (below), fix, and deploy again |
| 7 | The restore failed too | Possibly nothing | **Act now.** Over WireGuard: `sudo docker compose -p wassal-<env> ps`, then the logs. Deploy a known-good tag by hand (Rollback). The uptime alert is firing for production. |

On the host, over WireGuard:

```bash
cat /var/lib/wassal/prod/release /var/lib/wassal/prod/release.previous   # serving and previous tags
sudo docker compose -p wassal-prod ps
sudo docker logs --tail 100 wassal-prod-api-1
```

## Roll back

A rollback is an ordinary deploy of an older tag. **Migrations are never reversed**: every migration
must keep the previous release working (expand/contract), so the older code runs on the newer
schema.

- **From GitHub:** in Actions → `backend-release`, open the run for the tag you want, then choose
  **Re-run all jobs**. Production serves it again within about 10 minutes.
- **From the host**, over WireGuard as `ubuntu`:

  ```bash
  sudo env SSH_ORIGINAL_COMMAND='prod v1.2.2' /opt/wassal/bin/deploy --only prod
  sudo env SSH_ORIGINAL_COMMAND='staging sha-<commit>' /opt/wassal/bin/deploy --only staging
  ```

Deploying the tag that is already serving changes nothing. It only re-checks `/readyz` and the
release on both ports.

## Rehearse the failure paths

These run the real failure and restore code against staging's containers, without a broken image.
In Actions → `backend` → **Run workflow**, choose branch `master` and set `rehearse` to one of:

| `rehearse` | Expect |
| --- | --- |
| `migrate-fail` | The deploy fails with exit 5. Staging keeps serving its release, and GitHub emails the failure. |
| `verify-fail` | The new containers start and fail verification, then the previous release is restored and the deploy exits 6 |

The job uses the newest `master` commit that has an image. Poll production during both runs
(`while sleep 1; do curl -s -o /dev/null -w '%{http_code}\n' https://api.<host>/healthz; done`):
it must answer `200` throughout (quickstart scenarios 11 and 12).

## One-time setup

Do these before the first merge (task T061).

1. **GitHub Environments** (Settings → Environments). Their secrets reach the host, so a workflow
   edited on another branch must not be able to read them:
   - `staging`: under **Deployment branches and tags**, choose "Selected branches and tags" and add
     the branch rule `master`.
   - `production`: the same, with the tag rule `v*` only.
   - Recommended: add yourself as a required reviewer on `production`. Every release then waits for
     a click, so a bad commit on `master` can't reach production on its own (security review).
   - Under Settings → Branches, protect `master`: require a pull request and the `backend` and
     `gitleaks` checks.
2. **Deploy keys and peers:** follow provision-host.md step 8. It creates one WireGuard peer and one
   forced-command SSH key per environment, and the three secrets `WG_CONFIG`, `DEPLOY_SSH_KEY` and
   `DEPLOY_KNOWN_HOSTS` in each GitHub Environment.
3. **Make the image public.** GHCR creates the package as private on the first `master` push, and
   the host pulls without credentials. Under your GitHub profile → Packages → `wassal-backend` →
   Package settings, change the visibility to **Public**. The image holds no secrets (research R12).
   Until you do, deploys fail with exit 4.
4. **Failure emails:** under GitHub → Settings → Notifications → Actions, turn on email for failed
   workflows. That email is the deploy alert (FR-038).

### Replacing a deploy key

1. Remove the old key's line from `~deploy/.ssh/authorized_keys`.
2. Run `sudo wg-peer remove deploy-<env>`.
3. Repeat provision-host.md step 8 for that environment, and replace the three secrets.

## Updating the edge or the host scripts

The edge (`backend/docker/edge/`) and the host scripts (`backend/docker/host/`) are not deployed by
CI. After a change merges, copy them to the host and re-run the provisioning script.

- It installs the scripts and reloads Caddy.
- It re-applies the firewall only if the rules changed. Applying restarts Docker, and with it every
  container, production's included.
- It also installs pending package updates, and an update of Docker restarts the containers too. Run
  it in a quiet hour.

```bash
rsync -a --delete backend/docker/ ubuntu@10.66.0.1:wassal-docker/
ssh ubuntu@10.66.0.1 sudo ./wassal-docker/host/provision.sh
```

Run them from the repository root, over WireGuard. (`scp -r` into an existing `wassal-docker`
directory would nest the copy one level down.)
