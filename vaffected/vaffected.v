// vaffected tracks which test files a set of source changes can affect.
// Inputs are plain data: a project root and relative changed .v paths (git
// diff output upstream). Everything else is pure V — no subprocesses, the
// same discipline as vrepo.
module vaffected

import os

// VFile is one scanned source file of a project, relative to the project
// root. path is always normalized to forward slashes: 'vrepo/vrepo.v'.
pub struct VFile {
pub:
	path    string // relative, forward slashes: 'vrepo/vrepo.v'
	module  string // declared module
	imports []string
	is_test bool // *_test.v
}

// skip_dirs are not descended into when collecting a project's sources.
// 'testdata' is skipped so fixture projects are never treated as parts of
// the scanned root; scanning a fixture explicitly (tests do) still works.
const skip_dirs = ['bin', 'testdata', '.git', '.github']!

// collect_files walks the project under root and parses the module
// declaration and imports out of every .v file.
pub fn collect_files(root string) ![]VFile {
	mut files := []VFile{}
	mut queue := ['.']
	for queue.len > 0 {
		rel_dir := queue.last()
		queue.delete_last()
		ents := os.ls(os.join_path(root, rel_dir)) or {
			return error('vaffected: cannot read ${rel_dir}: ${err.msg()}')
		}
		for ent in ents {
			if ent.starts_with('.') {
				continue
			}
			rel := if rel_dir == '.' { ent } else { rel_dir + '/' + ent }
			if os.is_dir(os.join_path(root, rel)) {
				if ent in skip_dirs {
					continue
				}
				queue << rel
				continue
			}
			if !ent.ends_with('.v') {
				continue
			}
			files << parse_file(root, rel)
		}
	}
	return files
}

// affected_report returns the affected *_test.v paths, one per line, or ''
// when the change touches nothing the tested packages depend on.
pub fn affected_report(root string, changed []string) !string {
	files := collect_files(root)!

	// Seed the affected key set with the packages of the changed files and
	// propagate it backwards through every in-tree import until stable.
	mut keys := map[string]bool{}
	for c in changed {
		rel := c.replace('\\', '/')
		if rel.ends_with('.v') {
			keys[dot_key(rel)] = true
		}
	}
	propagate(files, mut keys)

	mut rows := []string{}
	for f in files {
		if f.is_test && dot_key(f.path) in keys {
			rows << f.path
		}
	}
	rows.sort()
	if rows.len == 0 {
		return ''
	}
	return rows.join('\n') + '\n'
}

// propagate extends the affected key set backwards through imports: a file
// whose import resolves to an affected in-tree package becomes affected, so
// its own package joins the set. Repeat until stable. Conservative by
// construction: ambiguous import targets resolve to every candidate.
fn propagate(files []VFile, mut keys map[string]bool) {
	mut suffixes := map[string][]string{}
	for f in files {
		register_suffixes(dot_key(f.path), mut suffixes)
	}
	for changing := true; changing; {
		changing = false
		for f in files {
			key := dot_key(f.path)
			if key in keys {
				continue
			}
			for imp in f.imports {
				if import_hits(imp, suffixes, keys) {
					keys[key] = true
					changing = true
					break
				}
			}
		}
	}
}

// import_hits reports whether an import string can resolve to a package key
// that is in the affected set. Only affected keys matter; unaffected keys
// are ignored so stdlib and external imports are never spuriously hit.
fn import_hits(imp string, suffixes map[string][]string, keys map[string]bool) bool {
	mut plain := imp.trim_space()
	if at := plain.index(' as ') {
		plain = plain[..at].trim_space()
	}
	for cand in suffixes[plain] {
		if cand in keys {
			return true
		}
	}
	return false
}

// register_suffixes indexes a package key under every dotted suffix, so an
// import with unknown leading segments (gil_silva.vrepo.vrepo) still matches
// the in-tree package ('vrepo').
fn register_suffixes(key string, mut tree map[string][]string) {
	parts := key.split('.')
	for start in 0 .. parts.len {
		tree[parts[start..].join('.')] << key
	}
}

// parse_file reads one source file and extracts its module and imports.
// Leading, trailing and inline comments are stripped before classification,
// so commented-out imports don't count as dependencies.
fn parse_file(root string, rel string) VFile {
	lines := os.read_lines(os.join_path(root, rel)) or { []string{} }
	mut module := 'main'
	mut imports := []string{}
	for raw_line in lines {
		mut line := raw_line.trim_space()
		if line.starts_with('//') {
			continue
		}
		if at := line.index('//') {
			line = line[..at].trim_space()
		}
		if line.starts_with('import ') {
			imports << line[6..].trim_space()
			continue
		}
		if line.starts_with('module ') {
			module = line[6..].trim_space()
		}
	}
	return VFile{
		path:    rel
		module:  module
		imports: imports
		is_test: rel.ends_with('_test.v')
	}
}

// dot_key maps a relative file path to its dotted package key:
// `vrepo/vrepo.v` → 'vrepo', `sub/util/parser.v` → 'sub.util'. Root-level
// files (module main, unimportable) share the synthetic 'main' key.
fn dot_key(path string) string {
	dir := os.dir(path)
	if dir == '.' {
		return 'main'
	}
	return dir.replace('/', '.')
}
// demo: lib change
