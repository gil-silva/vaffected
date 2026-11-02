// Tests for the other package.
module other

import fixsub

fn test_wrap() {
	assert wrap() == '[fixture help text]'
}
