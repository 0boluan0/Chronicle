# Separate evidence, work blocks, and review snapshots

Chronicle keeps observed activity as evidence, editable work blocks as the user's working interpretation, and completed review snapshots as immutable confirmed history. Activities are not renamed into work blocks, and a snapshot copies effective block values instead of relying only on live foreign keys, because automatic reconstruction must remain possible before review without silently changing or invalidating history after review or after evidence deletion.
