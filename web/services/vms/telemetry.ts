import {
  recordSpanError,
  setSpanAttributes,
  withSpan,
  type MaybeAttributes,
  type SpanCallback,
} from "../telemetry";

const VM_SUBSYSTEM = "vm-cloud";

export { recordSpanError, setSpanAttributes };
export type { MaybeAttributes, SpanCallback };

export async function withVmSpan<T>(
  name: string,
  attributes: MaybeAttributes,
  fn: SpanCallback<T>,
): Promise<T> {
  return withSpan(
    "cmux-vm",
    name,
    {
      "cmux.subsystem": VM_SUBSYSTEM,
      "cmux.runtime": "provider-driver",
      ...attributes,
    },
    fn,
  );
}

export async function withRivetActorSpan<T>(
  actorName: string,
  actionName: string,
  attributes: MaybeAttributes,
  fn: SpanCallback<T>,
): Promise<T> {
  return withSpan(
    "cmux-rivet",
    `cmux.rivet.${actorName}.${actionName}`,
    {
      "cmux.subsystem": VM_SUBSYSTEM,
      "cmux.runtime": "rivetkit",
      "rivet.actor": actorName,
      "rivet.action": actionName,
      ...attributes,
    },
    fn,
  );
}
