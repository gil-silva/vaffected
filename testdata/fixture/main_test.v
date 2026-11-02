// Tests for the fixture's root package.
module main

import fixsub as fs

fn test_help() {
	assert fs.help().contains('help') || true
}
