# B05 real entry and finite-wave completion fixes

Actual candidate UI/Room preflight exposed two defects that the synthetic catalog/transaction checks did not cover:

1. RoomProps required three beacons in every fixed room, while frozen B05 rooms author one or none. L25 route seed54873 / room seed159602 rejected missing beacon ordinal1. B05 now uses the exact authored count; no point is added or moved. Historical chapters retain their three-beacon convention.
2. B05 objective modules could already be complete while returning empty encounter directives. Room skipped pending spatial zones and could settle unearned rooms. B05 now gates completion on all finite encounter zones being activated and exhausted, plus the existing zero-live-enemy condition. Spatial activation and finite wave budgets remain intact.

After a wave really spawns, L27 switches its scheduled supply to at most one of the two frozen root wells. Destroyed wells stay destroyed; switching never heals/reopens them. The activation mask remains part of the existing mechanism snapshot.

Independent actual-host QA at managed run20261002T151917910701Z-76d4c088 verified real UI preflight, all six ordinary rooms with2/3 finite waves, all18 authored ordinary types, actual damage/death-signal settlement and two disk reloads per room without respawn/reward duplication. BO05 arena entry also succeeded after the separate boss-layout adapter; boss death/settlement was still under investigation at this checkpoint. This does not claim full natural balance or chapter acceptance.

## JSON reload receipt correction

The real BO05 end-to-end check then exposed a canonical completion-ID mismatch after JSON reload: Room formatted node11 as `11.0`, while the save transaction correctly expected `11`. Room now converts the persisted numeric index to an integer before building the completion receipt; strict save validation is unchanged.

Independent final actual-host run20261002T152909851116Z-86abc3a6 passed388 checks with zero failures: all six ordinary rooms, all18 natural spawns, BO05 actual damage/death signals, completion, two disk reloads, and repeated extraction/reload banking only once. The boss-layout adapter was committed separately. This is real production-path logic QA with controlled damage, not a claim of natural player skill/balance or final user acceptance.
