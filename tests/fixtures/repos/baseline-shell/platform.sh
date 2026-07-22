# Fixture platform.sh for baseline-setup's bats fixtures — translates FIXTURE_PLATFORM_*
# overrides (set by the test, before invoking baseline-setup.sh as a subprocess) into the real
# PLATFORM_* exports, so an integration test can control GUI/DE without a real graphical session.
# Defaults to a GUI/GNOME host so a golden-run test that sets nothing still exercises every layer.
PLATFORM_FAMILY="${FIXTURE_PLATFORM_FAMILY:-debian}"
PLATFORM_PKG="${FIXTURE_PLATFORM_PKG:-apt}"
PLATFORM_ATOMIC="${FIXTURE_PLATFORM_ATOMIC:-0}"
PLATFORM_GUI="${FIXTURE_PLATFORM_GUI:-1}"
PLATFORM_DE="${FIXTURE_PLATFORM_DE:-gnome}"
export PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_GUI PLATFORM_DE
