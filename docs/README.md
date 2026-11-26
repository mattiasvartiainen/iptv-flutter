# IPTV Documentation

TV-first IPTV for Android (phone/TV), Windows and LG webOS; Linux is a
development/testing target. This index distinguishes implemented architecture,
approved plans and historical evidence.

## Current authority: read in this order

1. [Agent guide](../AGENTS.md) and [work-package status](architecture-code-improvements.md)
   — select an unblocked package; completion entries supersede original audit findings.
2. [Architecture rules tests](../test/architecture/architecture_rules_test.dart)
   — executable boundary checks; source/tests/configuration/migrations define
   implemented behavior when older prose disagrees.
3. [Current architecture](architecture.md) and [decisions](decisions.md)
   — ownership, platform boundaries, verified facts and human decision gates.
4. [Cross-device design contract](design-guidelines.md) and
   [Product & UX requirements](IPTV_App_Product_UX_Requirements.md) — product
   intent and input/accessibility requirements, not proof of implementation.
5. The feature-specific plans below — only selected, approved work is authorized.

## Active plans and engineering references

- [Xtream and metadata](xtream-and-metadata-implementation-plan.md): mixed
  implemented/planned scope; its status and work packages distinguish them.
- [Design evolution](design-evolution-implementation-plan.md): selected
  presentation work, subject to decision gates.
- [Catalog redesign](catalog-import-and-browsing-redesign.md) and
  [2026-09-28 implementation steps](implementation-steps-2026-09-28.md):
  design lineage of the production v9 catalog pipeline, not the latest schema.
  [Append-only migrations](../lib/services/storage/storage_migrations.dart)
  and [migration tests](../test/services/storage/database_migrations_test.dart)
  are the executable schema record.
- [Telemetry](telemetry.md): implemented diagnostics and remaining verification.
- [Import performance](import-performance.md): dated measurements and rationale;
  old bottlenecks/targets are not current findings or hardware certification.
- [Research](research.md), [UX implementation specification](iptv_ux_implementation_spec.md)
  and [Kanal concept](Kanal_%20IPTV%20TV%20experience%20concept.html):
  references/inspiration, not authority to change behavior or adopt branding.

## Historical documents: do not implement from these alone

| Document | Meaning today |
|---|---|
| [Original product requirements](product-requirements.md) | Initial webOS MVP; exclusions do not override approved Series/Xtream work. |
| [Original implementation plan](implementation-plan.md), [initial agent handoff](agent-handoff.md) | First-scaffold sequence, not current coding instructions. |
| [Import plan 2](implementation-plan2.md), [plan 3](implementation-plan3.md), [plan 4](implementation-plan4.md) | Earlier import designs; superseded by the production v9 pipeline and later work packages. |
| [Original improvement notes](improvements-1.md) | Historical audit/bottleneck evidence; reverify before treating any finding as current. |
| [Phase 0 baseline](phase0-baseline.md) | A dated benchmark, not current performance or device validation. |
| [Storage research](storage.md), [reference SQL](database-schema.md), [schema v1](schema_v1.sql) | Research/reference artifacts, not migrations to apply. |
| [Architecture audit checklist](flutter-architecture-engineering-audit.md) | Reusable analysis prompt, not an executed current audit. |

Sections 2-4 of the [architecture improvement plan](architecture-code-improvements.md)
retain the original audit snapshot, with some later annotations. Section 1 records
delivery status; section 5 and the executable tests define current guardrails.
Historical text remains for traceability, not as an active defect backlog.

## Documentation rule

Update directly related current docs and work-package status with implementation.
Preserve historical measurements and label their scope rather than rewriting
history. A plan or benchmark does not prove hardware behavior. Keep unresolved
human decisions explicit and never infer authorization from an old checklist.
