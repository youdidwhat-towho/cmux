import { actor } from "rivetkit";
import { getProvider, type ProviderId, type VMStatus } from "../drivers";

export type VMState = {
  provider: ProviderId;
  providerVmId: string; // also the actor key now — no cmux UUID layer.
  userId: string;       // Stack Auth user id, immutable after create.
  image: string;
  status: VMStatus;
  createdAt: number;
  pausedAt: number | null;
  /**
   * Monotonic counter of disconnects. Every `onDisconnect` increments this and schedules an
   * autoPause keyed on the new value. `autoPause` then checks that its captured epoch still
   * matches — otherwise a later reconnect/disconnect cycle has opened a fresh idle window
   * and the old timer should not fire. Fixes the race CodeRabbit flagged: without this,
   * a disconnect at t=0 schedules a pause at t=10min, a reconnect at t=5min, and a later
   * disconnect at t=6min all coexisted, and the t=0 timer could pause the VM ~4 minutes
   * into the new 10-minute window.
   */
  idleEpoch: number;
  snapshots: Array<{ id: string; name?: string; createdAt: number }>;
};

export type VMCreateInput = {
  provider: ProviderId;
  providerVmId: string;
  userId: string;
  image: string;
};

const IDLE_PAUSE_MS = 10 * 60 * 1000;

// One actor per VM. Actor key is the provider's own id. The provider VM is already created by
// the caller (userVmsActor.create) before we spawn this actor — we just own lifecycle, idle
// auto-pause, and per-VM actions (exec, snapshot, openSSH, remove, …).
export const vmActor = actor({
  options: { name: "VM", icon: "cloud" },

  createState: (_c, input: VMCreateInput): VMState => ({
    provider: input.provider,
    providerVmId: input.providerVmId,
    userId: input.userId,
    image: input.image,
    status: "running",
    createdAt: Date.now(),
    pausedAt: null,
    idleEpoch: 0,
    snapshots: [],
  }),

  onDestroy: async (c) => {
    if (c.state.status !== "destroyed" && c.state.providerVmId) {
      try {
        await getProvider(c.state.provider).destroy(c.state.providerVmId);
      } catch {
        // Best-effort; provider may have already evicted the VM.
      }
    }
  },

  onConnect: (_c, _conn) => {
    // New client attached. autoPause re-checks conns.size before pausing, so a reconnect race
    // is a no-op; nothing to explicitly cancel here.
  },

  onDisconnect: (c, _conn) => {
    if (c.conns.size === 0) {
      c.state.idleEpoch += 1;
      void c.schedule.after(IDLE_PAUSE_MS, "autoPause", c.state.idleEpoch);
    }
  },

  actions: {
    autoPause: async (c, epoch: number) => {
      // Skip if a later reconnect/disconnect cycle has bumped the epoch — otherwise the
      // old timer could pause the VM mid-way through the newest idle window.
      if (epoch !== c.state.idleEpoch) return;
      if (c.conns.size !== 0) return; // raced with a reconnect
      if (c.state.status !== "running") return;
      await getProvider(c.state.provider).pause(c.state.providerVmId);
      c.state.status = "paused";
      c.state.pausedAt = Date.now();
    },

    pause: async (c) => {
      if (c.state.status === "paused") return;
      await getProvider(c.state.provider).pause(c.state.providerVmId);
      c.state.status = "paused";
      c.state.pausedAt = Date.now();
    },

    resume: async (c) => {
      if (c.state.status === "running") return;
      const handle = await getProvider(c.state.provider).resume(c.state.providerVmId);
      c.state.providerVmId = handle.providerVmId;
      c.state.status = "running";
      c.state.pausedAt = null;
    },

    snapshot: async (c, name?: string) => {
      const ref = await getProvider(c.state.provider).snapshot(c.state.providerVmId, name);
      c.state.snapshots.push({ id: ref.id, name: ref.name, createdAt: ref.createdAt });
      return ref;
    },

    exec: async (c, command: string, timeoutMs?: number) => {
      return await getProvider(c.state.provider).exec(c.state.providerVmId, command, { timeoutMs });
    },

    openSSH: async (c) => {
      // Mints a short-lived SSH endpoint the mac client can dial directly. Freestyle returns a
      // real gateway endpoint (vm-ssh.freestyle.sh); E2B throws a clear error.
      return await getProvider(c.state.provider).openSSH(c.state.providerVmId);
    },

    status: (c) => c.state,

    remove: async (c) => {
      if (c.state.status !== "destroyed" && c.state.providerVmId) {
        try {
          await getProvider(c.state.provider).destroy(c.state.providerVmId);
        } catch {
          // Best-effort; actor destroy still runs below.
        }
      }
      c.state.status = "destroyed";
      c.destroy();
    },
  },
});
