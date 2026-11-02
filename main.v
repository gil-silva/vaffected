// vaffected CLI — print the test files a change can actually affect.
// Build: v .   (→ bin/vaffected)
// Run:   vaffected [--run] [root] [base]   (defaults: '.', 'HEAD')
//   --run hands the affected test files straight to `v test` and propagates
//   its exit code; without it the affected set is printed, one per line.
module main

import os
import vaffected

fn main() {
	mut run := false
	mut positional := []string{}
	for arg in os.args[1..] {
		if arg == '--run' {
			run = true
		} else {
			positional << arg
		}
	}
	root := if positional.len > 0 { positional[0] } else { '.' }
	base := if positional.len > 1 { positional[1] } else { 'HEAD' }

	// Changed source paths come from git; the library stays pure V and
	// receives them as data, exactly like vrepo receives its root.
	mut changed := []string{}
	git := os.exec(['git', 'diff', '--name-only', base])
	if git.exit_code != 0 {
		eprintln('vaffected: git diff failed: ${git.output.trim_space()}')
		exit(1)
	}
	for row in git.output.split('\n') {
		mut path := row.trim_space()
		if path.starts_with('"') {
			path = path.trim_left('"').trim_right('"')
		}
		// git reports repo-root-relative paths; the analysis root may be a
		// subdirectory, so re-express changed paths relative to root.
		prefix := if root == '.' { '' } else { root.trim_right('/') + '/' }
		if prefix.len > 0 && path.starts_with(prefix) {
			path = path[prefix.len..]
		}
		if path.len > 0 && path.ends_with('.v') {
			changed << path
		}
	}

	out := vaffected.affected_report(root, changed) or {
		eprintln('vaffected: ${err.msg()}')
		exit(1)
	}
	if out.len == 0 {
		println('no affected tests (nothing to re-run)')
		return
	}
	if !run {
		print(out)
		return
	}
	files := out.split('\n').filter(it.len > 0)
	println('running v test ${files.join(' ')}')
	t := os.exec(['v', 'test', ...files])
	print(t.output)
	exit(t.exit_code)
}
