# Superseded: schema v1

This capture states `schema_version: 1` and names
`scripts/capture-runtime-evidence.sh`, an instrument this tree no longer carries.
It predates the evidence classes, the per-probe stream records, and the
single-instance binding, so it is retained as history rather than validated
against the v2 contract.

The composite defect that motivated the v2 rewrite is present here: declarations
and observations in this document are not bound to one identified QEMU instance.
`docs/audits/runtime-evidence-capture-protocol.md` carries the current contract.
