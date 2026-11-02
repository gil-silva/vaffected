// fixture CLI entry: depends on fixsub via an aliased import.
module main

import fixsub as fs

fn main() {
	println(fs.help())
}
