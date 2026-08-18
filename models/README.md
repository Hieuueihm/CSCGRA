# Reference models

Reference and golden-model implementations live here. The active paper and
release flow uses `models/golden` to generate the v2 K-sweep include; compiled
testbench vectors remain under `verification/v2`. The matching v1 vectors are
retained under `archive/v1/verification` only as historical provenance.

Models are not synthesizable source and are not automatically compiled by the
canonical RTL flow. Treat frozen golden inputs as independent correctness
references; do not modify them to accommodate an RTL regression.
