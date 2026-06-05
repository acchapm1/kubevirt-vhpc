# Plan: Predefined Cluster Templates (`just intro` / `just inter`)

> Status: Planning
> Created: 2026-06-05
> Stack: KubeVirt VMs on Kubernetes (minikube), Rocky Linux GenericCloud qcow2 + CDI
> Target: `rocky9/` first (canonical variant), then port to `rocky10/`

<!-- TRACKER MODE active. Tick `- [ ]` boxes as each step lands; mark blockers
     with ⚠️ + a one-line note. This file is the source of truth. -->

## Progress

- [ ] Phase 1 — `just intro` (rocky9)
- [ ] Phase 2 — `just inter` (rocky9)
- [ ] Phase 3 — Docs (README/HOWTO/AGENTS)
- [ ] Phase 4 — Port to rocky10

## Goal

Add two predefined, one-command cluster templates so a student can stand up a
fully-configured KubeVirt cluster with a single command:

| Command      | Template  | Topology                                          |
| ------------ | --------- | ------------------------------------------------- |
| `just intro` | **Intro** | 1 head, 2 compute, 1 storage (NFS → `/scratch`)   |
| `just inter` | **Inter** | 1 head, 2 compute, 4 storage (3 disks each)       |

Each command does **everything**: generate manifests → install KubeVirt/CDI (if
needed) → deploy VMs → wait for them → wire SSH → provision storage/mounts →
show status. End state is a running, usable cluster.

## Stack notes (vs. the Docker Compose original)

This repo deploys VMs via **KubeVirt**, not containers via docker-compose. That
changes several implementation details vs. the docker-vhpc plan:

- **Nodes are real VMs** (`VirtualMachine` CRs) booting the Rocky GenericCloud
  qcow2, imported once by **CDI** (`dataVolumeTemplates`, `http` source). No
  Dockerfiles, no image build.
- **Provisioning is cloud-init**, not entrypoint scripts: see
  `manifests/config/cloud-init-{head,compute,storage}.yaml` (each a `Secret` with
  `#cloud-config` userdata). VMs run a **real kernel + systemd**, so NFS uses the
  in-kernel **`nfs-server`** (no nfs-ganesha workaround needed) and persistence
  uses **systemd/fstab** (no supervisord hook).
- **Extra drives are real virtio block devices**, not loopback files. Attach an
  extra `disk` backed by a PVC to the VM and the guest sees a real `/dev/vdb` —
  **no `losetup`, no loop-device collision constraint**. This is the biggest
  simplification over the docker-vhpc plan.
- **Naming**: `head`, `compute1..N`, `storage`, `storage2..N`; namespace
  `{VARIANT}-cluster` (default `hpc-cluster`). Manifests are generated into
  `generated/` by `scripts/generate-config.sh`.
- **Networking/DNS**: VMs reach each other by service/hostname; the storage
  export is reachable at `storage.{VARIANT}-cluster.svc.cluster.local:/export`
  (the existing ansible playbook already references this form).

## Template Specifications

### Template 1 — Intro

- **1 head**, **2 compute**, **1 storage** (the base topology:
  `COMPUTE_NODES=2`, `STORAGE_NODES=1`).
- The storage VM runs the kernel **NFS server** exporting `/export` (already the
  default in `cloud-init-storage.yaml`). Back `/export` with the existing
  `storage-data` PVC (the `nfsdata` virtio disk) so exported data persists.
- The head VM **and** both compute VMs mount that export as **`/scratch`** over
  NFS.
- This is essentially the base cluster plus an automated NFS-client `/scratch`
  mount, persistent across VM reboots.

### Template 2 — Inter

- **1 head**, **2 compute**, **4 storage**.
- Each storage VM presents **3 disks**:
  - `vda` → the OS root (the CDI-imported Rocky rootdisk; nothing to add).
  - `vdb`, `vdc` → **raw, unformatted virtio block devices**, left for the
    student to format/configure later for parallel filesystems (BeeGFS, Lustre,
    Ceph).
- `vdb`/`vdc` are backed by **dedicated PVCs (5Gi each)** attached as extra
  KubeVirt `disk`s. The guest kernel exposes them as real `/dev/vdb` and
  `/dev/vdc` — device names match the spec with no symlink/loopback trickery.
- No `/scratch` NFS auto-mount is required for Inter (storage VMs here are PFS
  targets, not a shared NFS scratch). The Inter storage VMs come up bare (NFS
  server off), ready for BeeGFS/Lustre/Ceph.

## Design Decisions (to confirm)

1. **`/scratch` mount → via Ansible.** Repair and reuse the existing Ansible
   playbook (`rocky9/ansible/playbook.yaml`), which currently mounts the wrong
   path (`/shared`) and only targets compute. Mount `/export` as **`/scratch`**
   on **head + both compute** VMs, persistently (fstab + a systemd mount unit so
   it re-mounts on reboot). `just intro` runs the playbook as its final step.
   - Ansible reaches VMs over **SSH** (real sshd is present). Inventory must be
     generated/refreshed to match the live VM names and reach them via the
     in-cluster network (or `kubectl exec` as a fallback connection).
2. **Inter extra drives → extra PVC-backed virtio disks.** Two 5Gi PVCs per
   storage VM (`storageN-vdb`, `storageN-vdc`), attached as extra `disk`s in the
   VM spec, surfaced as real `/dev/vdb`/`/dev/vdc`. Left **unformatted** (no
   `mkfs`) — students do that. Real block devices give true Ceph-OSD / Lustre
   semantics.
3. **Persistent across reboots.** PVCs persist the extra disks across VM
   restart/redeploy; `/scratch` is re-mounted on every boot (fstab + systemd).
   Survives `virtctl restart`/VM reschedule and `just delete-vms && just
   deploy-generated` (PVCs retained unless explicitly deleted).
4. **rocky9 first, then rocky10.** rocky9 is the canonical variant; rocky10
   mirrors its layout and is a follow-up port.

## Implementation Plan

### Phase 1 — `just intro` (rocky9)

**1.1 Make the storage export persistent + reachable**

- [ ] Confirm `cloud-init-storage.yaml` exports `/export` over kernel NFS and
  that `/export` is backed by the `storage-data` PVC (mount the `nfsdata` disk
  at `/export` in cloud-init so exported data survives reboot).
- [ ] Confirm the NFS service name/DNS the clients will mount
  (`storage.{VARIANT}-cluster.svc.cluster.local` or the VMI hostname) and that
  `manifests/services/nfs-service.yaml` exposes 2049.

**1.2 Fix the Ansible NFS-client provisioning**

- [ ] Rewrite `rocky9/ansible/inventory.yaml` to match live VM names and group
  them by role (`head`, `compute`, `storage`) with a combined `nfs_clients`
  group (head + compute). Decide the connection: SSH (via the head/NodePort or
  in-cluster) or `kubectl exec`. Generate it from the live cluster if names are
  dynamic.
- [ ] Rewrite `rocky9/ansible/playbook.yaml`:
  - NFS-mount play targets **`nfs_clients`** (head + compute only), not all.
  - Mountpoint is **`/scratch`** (currently `/shared`); source is the discovered
    storage node / NFS service.
  - **Persistent**: `/etc/fstab` entry (`nfsvers=4,_netdev,nofail`) **and** a
    systemd mount/automount unit (or `x-systemd.automount`) so it re-mounts on
    every boot — VMs have systemd, so no supervisord hook is needed.
  - Make it idempotent.

**1.3 Add a reusable `mount-scratch` recipe (the worker)**

- [ ] `rocky9/Justfile` recipe `mount-scratch` runs the playbook against the
  live cluster (`ansible-playbook -i ansible/inventory.yaml ...`), plus an
  `ansible-setup` dependency that provisions the env.
- [ ] Provision Ansible via a **uv-managed env** in `ansible/` (`just
  ansible-setup` → `uv sync`); no global Ansible needed.

**1.4 Add the `intro` recipe**

```just
# Launch the Intro template: 1 head, 2 compute, 1 storage + NFS /scratch
intro:
    @just generate-config       # COMPUTE_NODES=2, STORAGE_NODES=1 (base layout)
    @just deploy-generated      # or full-deploy if KubeVirt/CDI not yet installed
    @just _wait-ready           # wait for VMIs to be Running + agent-connected
    @just copy-ssh-key
    @just mount-scratch         # NFS /export -> /scratch on head + compute
    @just status
```

- `intro` pins `COMPUTE_NODES=2`, `STORAGE_NODES=1` (base topology already
  matches; reuse `generate-config → deploy-generated`).
- Add a `_wait-ready` helper (`kubectl wait` on the VMIs / readiness loop) so the
  one-command flow doesn't race cloud-init.
- Final state: head + 2 compute + 1 storage running, passwordless SSH wired,
  `/scratch` mounted on head + compute.

**1.5 Verify Intro**

- [ ] `just generate-config` then validate the merged manifests
  (`kubectl apply --dry-run=client -f generated/`) + ansible syntax-check.
- [ ] `just intro` from a clean slate → 4 VMs Running, Ansible recap 0 failed.
  `/scratch` round-trip: head writes a file, **both** compute VMs read the same
  bytes back; storage VM correctly has no `/scratch`.
- [ ] Persistence: restart the head VM (`virtctl restart head` / delete the VMI)
  → `/scratch` auto-remounts via fstab/systemd; the pre-restart file survives.

### Phase 2 — `just inter` (rocky9)

**2.1 Multi-drive storage support**

- [ ] Parameterize the storage VM template (`scripts/generate-config.sh` /
  `scale-storage.sh`) to optionally attach **extra virtio disks** backed by
  per-VM PVCs: for each name in `EXTRA_DRIVES` (e.g. `vdb vdc`), add a `disk`
  entry + a `volume` referencing a `storageN-<name>` PVC, and emit the matching
  `PersistentVolumeClaim` (size `EXTRA_DRIVE_SIZE_GB`, default 5Gi). **No `mkfs`**
  — disks ship raw.
- [ ] Inter storage VMs come up with the NFS server **off** (a cloud-init
  variant / flag), so they idle bare, ready for BeeGFS/Lustre/Ceph.

**2.2 Inter manifest generation**

- [ ] Add a dedicated **`_inter-config`** generation path (cleaner than
  overloading `generate-config`): emit `head`, `compute1/2`, and `storage`
  through `storage4`, where **all four storage VMs are identical** (bare,
  vdb+vdc, NFS off), each with its own `storageN-vdb` / `storageN-vdc` PVCs.
- [ ] Add a cloud-init for bare Inter storage (no NFS export) or a toggle on the
  existing `cloud-init-storage` so storage1 matches storage2/3/4.

**2.3 Add the `inter` recipe**

- [ ] `inter` recipe: `_inter-config → deploy-generated → _wait-ready →
  copy-ssh-key → status`. 2 compute (base), 4 storage (all with vdb/vdc). No
  `/scratch` NFS mount (storage VMs are PFS targets).

**2.4 Verify Inter**

- [ ] Validate the generated Inter manifests (`kubectl apply --dry-run`).
- [ ] `just inter` from clean slate → 7 VMs (head + 2 compute + 4 storage). All
  4 storage VMs expose **real** `/dev/vdb` + `/dev/vdc`, each ~5Gi and **raw**.
  `mkfs.xfs /dev/vdb` and `pvcreate /dev/vdc` both succeed.
- [ ] Persistence: restart a storage VM → the extra disks re-attach from their
  PVCs; data on `vdb`/`vdc` persists.

### Phase 3 — Docs

- Update `rocky9/README.md`, `rocky9/HOWTO.md`, and `AGENTS.md` command list
  with `just intro` and `just inter`.
- Add a short "Templates" section: what each provisions, the `/scratch` NFS
  workflow (Intro), and the `vdb`/`vdc` raw-drive workflow for BeeGFS/Lustre/Ceph
  (Inter), including the "format it yourself" note and example commands.
- Note the Ansible prerequisite for `just intro`.

### Phase 4 — Port to rocky10

- [ ] Realign `rocky10/` to the final rocky9 design (generation script, extra-disk
  template, cloud-init variants, recipes). Keep the Rocky 10 GenericCloud image
  URL.
- [ ] Port `just inter`: extra-PVC disk generation, `_inter-config`, `inter`
  recipe, bare-storage cloud-init.
- [ ] Port `just intro`/`mount-scratch` (kernel NFS works the same on EL10) — or
  stub with a "use rocky9" message if a blocker appears.
- [ ] rocky10 docs (README/HOWTO/commands) for both templates.
- [ ] Verify: dry-run validate + a live `just inter` (and `just intro`) run on
  rocky10.

## Files Touched (rocky9)

### Phase 1 — planned (change/add)

| File | Change |
| ---- | ------ |
| `rocky9/Justfile` | add `intro`, `mount-scratch`, `ansible-setup`, `_wait-ready` |
| `rocky9/ansible/inventory.yaml` | role groups + `nfs_clients`; SSH or `kubectl exec` connection; match live VM names |
| `rocky9/ansible/playbook.yaml` | mount `/export`→`/scratch` on `nfs_clients` (was `/shared`/compute-only); persistent via fstab + systemd; idempotent |
| `rocky9/ansible/ansible.cfg` | new — inventory, `host_key_checking=False`, interpreter pin |
| `rocky9/ansible/pyproject.toml`, `uv.lock`, `.python-version` | new — uv project, Python 3.12, `ansible`+deps |
| `rocky9/manifests/config/cloud-init-storage.yaml` | mount `nfsdata` PVC at `/export`; confirm kernel NFS export persists |
| `rocky9/manifests/services/nfs-service.yaml` | confirm/expose NFS (2049) for client mounts |
| `.gitignore` | ignore `.venv/`, `__pycache__/`, `*.pyc`, `generated/` |

### Phase 2 — planned (change/add)

| File | Change |
| ---- | ------ |
| `rocky9/scripts/generate-config.sh` | extra-disk support on storage VMs (per-VM `vdb`/`vdc` PVCs + disk entries) |
| `rocky9/scripts/scale-storage.sh` | same extra-disk support for scaled storage nodes |
| `rocky9/Justfile` | add `inter` + `_inter-config` (4 uniform storage VMs w/ vdb/vdc, NFS off) |
| `rocky9/manifests/config/cloud-init-storage.yaml` | NFS-off toggle/variant for bare Inter storage |

### Phase 3/4 — planned

| File | Change |
| ---- | ------ |
| `rocky9/README.md`, `rocky9/HOWTO.md`, `AGENTS.md` | document both templates |
| `rocky10/**` | realign to rocky9, replicate Phases 1–3 |

## Open Items / Risks

- **Ansible connection to VMs** — over the pod network (SSH to VMI IPs from a
  jump, NodePort, or `kubectl exec` connection plugin). Decide before 1.2; the
  current inventory assumes name-resolvable SSH hosts.
- **`/export` persistence on the storage VM** — ensure the `nfsdata`/`storage-data`
  PVC is actually mounted at `/export` in cloud-init (currently `/export` is just
  `mkdir`'d; the PVC disk may be unmounted).
- **`generate-config` reuse vs. dedicated Inter generator** — decide whether to
  overload `generate-config` with an extra-drives flag or add `_inter-config`.
- **storage-01 uniformity** under Inter — make the base `storage` VM match the
  scaled `storage2/3/4` (all bare, vdb+vdc, NFS off).
- **Readiness/race on cloud-init** — the one-command flow needs a real wait gate
  (`_wait-ready`) so `copy-ssh-key`/`mount-scratch` don't run before sshd/NFS are
  up. CDI image import on first deploy can take several minutes.
- **PVC lifecycle on teardown** — `just delete-vms` deletes PVCs; document how to
  preserve `vdb`/`vdc` data across a redeploy if desired.

## Acceptance Criteria

- [ ] `just intro` → head + 2 compute + 1 storage running; `/scratch` mounted on
  head and both compute VMs; survives VM restart.
- [ ] `just inter` → head + 2 compute + 4 storage running; each storage VM
  exposes raw `/dev/vdb` and `/dev/vdc` (~5Gi, unformatted) plus its OS root;
  survives restart; a student can `mkfs`/`pvcreate` against vdb/vdc for BeeGFS,
  Lustre, or Ceph.
- [ ] Generated manifests validate (`kubectl apply --dry-run=client`) for Intro
  and Inter.
- [ ] Documented in README/HOWTO/AGENTS.
- [ ] Same delivered for `rocky10/` after rocky9 is verified.
