// Unit tests for vaffected, exercised against the bundled fixture project:
//
//	testdata/fixture
//	├── main.v / main_test.v        (module main, `import fixsub as fs`)
//	├── fixsub/fixsub.v             (leaf package)
//	├── fixsub/fixsub_test.v
//	├── other/other.v               (module other, `import fixsub`)
//	└── other/other_test.v
//
// Dependency edges for the expectations below: main → fixsub, other → fixsub,
// and nothing else.
module vaffected

import os

// fixture returns the absolute path of the bundled fixture project.
fn fixture() string {
	return os.join_path(@VMODROOT, 'testdata', 'fixture')
}

// rows runs the report and splits it back into paths.
fn affected_rows(changed ...string) []string {
	out := affected_report(fixture(), changed) or { panic('affected_report: ${err.msg()}') }
	return out.split('\n').filter(it.len > 0)
}

fn test_changed_leaf_reruns_dependents() {
	// fixsub changed → its own test plus every package that imports it.
	got := affected_rows('fixsub/fixsub.v')
	assert got.len == 3
	assert 'fixsub/fixsub_test.v' in got
	assert 'main_test.v' in got
	assert 'other/other_test.v' in got
}

fn test_two_hop_chain() {
	// other imports fixsub, nothing imports other; changing 'other/other.v'
	// must rerun only its own test file.
	got := affected_rows('other/other.v')
	assert got == ['other/other_test.v']
}

fn test_changed_root_main_reruns_own_test_only() {
	// Root package 'main' is unimportable; dependents cannot exist.
	got := affected_rows('main.v')
	assert got == ['main_test.v']
}

fn test_aliased_import_propagates() {
	// main.v imports fixsub through an alias (`import fixsub as fs`);
	// stripping the alias must not break propagation.
	got := affected_rows('fixsub/fixsub.v')
	assert 'main_test.v' in got
}

fn test_no_changes_runs_nothing() {
	assert affected_rows() == []
}

fn test_non_v_changes_ignored() {
	assert affected_rows('README.md', 'v.mod') == []
}

fn test_inner_file_of_nested_pkg() {
	// Deeper layouts map to dotted keys; here there is only one level, so
	// also exercise a changed test file directly.
	got := affected_rows('other/other_test.v')
	assert got == ['other/other_test.v']
}

// tmp_project builds a tiny in-memory project to exercise nested dotted keys
// and reported sorting.
fn tmp_project() string {
	root := os.join_path(os.temp_dir(), 'vaffected-tmp-${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'lib', 'util'), os.MkdirParams{}) or { return '' }
	os.mkdir_all(os.join_path(root, 'app'), os.MkdirParams{}) or { return '' }
	os.write_file(os.join_path(root, 'lib', 'util', 'util.v'), 'module util\n') or {}
	os.write_file(os.join_path(root, 'lib', 'util', 'util_test.v'), 'module util\n') or {}
	os.write_file(os.join_path(root, 'app', 'app.v'), 'module main\n\nimport lib.util\n') or {}
	os.write_file(os.join_path(root, 'app', 'app_test.v'), 'module main\n\nimport lib.util\n') or {}
	return root
}

fn test_nested_pkg_via_dotted_import() {
	root := tmp_project()
	defer {
		os.rmdir_all(root) or {}
	}
	out := affected_report(root, ['lib/util/util.v']) or { panic(err.msg()) }
	got := out.split('\n').filter(it.len > 0)
	// The import 'lib.util' resolves through suffix matching to the in-tree
	// 'lib.util' package, so BOTH its test and … the root package? No: only
	// the package that unambiguously depends on it reruns.
	assert got == ['app/app_test.v', 'lib/util/util_test.v']
}

fn test_error_on_missing_root() {
	affected_report(os.join_path(@VMODROOT, 'testdata', 'definitely-missing'), ['x.v']) or {
		assert true
		return
	}
	assert false
}
