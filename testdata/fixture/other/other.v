// fixture middle package: imports fixsub (transitive hop target).
module other

import fixsub

// wrap demonstrates a two-hop dependency chain main → other → fixsub.
pub fn wrap() string {
	return '[' + fixsub.help() + ']'
}
