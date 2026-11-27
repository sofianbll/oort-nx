import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RELEASE = Path(__file__).resolve().parents[2] / "scripts/release.sh"
PUBLIC = "fixture/NxLibrary"
OTHER = "fixture/oort-nx"
ENGINE = "https://github.com/fixture/nxnative"


class ReleaseTarget(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.app = self.root / "app"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.git = shutil.which("git")
        self.env = dict(
            PATH=f"{self.bin}:{os.defpath}",
            HOME=temp.name,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_ALLOW_PROTOCOL="file",
            GIT_AUTHOR_NAME="Fixture",
            GIT_AUTHOR_EMAIL="fixture@example.invalid",
            GIT_COMMITTER_NAME="Fixture",
            GIT_COMMITTER_EMAIL="fixture@example.invalid",
            REAL_GIT=self.git,
            FIXTURES=temp.name,
            CANONICAL=PUBLIC,
        )
        self.git_run("init", "-q", "-b", "main", str(self.app), cwd=self.root)
        self.write("VERSION", "0.3.1\n")
        self.write("notes.md", "Fixture release notes\n")
        self.write(".gitignore", "/work/\n/dist/\n")
        self.write("engines/nxnative/NxnativeAdapter/Setup/ToolchainRequirements.swift", 'minimumXcode: "27.2"\n')
        self.write("Tests/CatalogAppChecks/run_fixture.py", "")
        self.write("Tests/PublicationChecks/__init__.py", "")
        self.write("scripts/check_publication.py", "")
        self.write("scripts/check_localizations.py", "")
        self.write("scripts/build_dmg.sh", '''printf '%s\\n' "$@" > "$FIXTURES/dmg-args"
mkdir -p dist; touch "dist/Oort NX.dmg"
''')
        self.write("scripts/build_app.sh", '''python3 - "$1" <<'PY'
from pathlib import Path
import os, plistlib, sys
contents = Path(sys.argv[1]) / "Contents"
runtime = contents / "Resources/Runtime/python/bin"
runtime.mkdir(parents=True)
(runtime / "python3").symlink_to("/usr/bin/true")
(contents / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleShortVersionString": os.environ["NX_VERSION"],
    "NXLibraryRelease": True,
    "NXLibraryEngineRepository": os.environ["NX_ENGINE_REPO"],
    "NXLibraryEngineCommit": os.environ["NX_ENGINE_COMMIT"],
}))
PY
''')
        (self.app / "work/Runtime").mkdir(parents=True)
        script = self.app / "scripts/release.sh"
        shutil.copyfile(RELEASE, script)
        self.write(
            "core/OortLibrary/App/AppUpdate.swift",
            f'let defaultRepository: String? = "{PUBLIC}"\n'
            f'let successorRepository: String? = "{OTHER}"\n',
        )
        self.git_run("add", ".")
        self.git_run("commit", "-qm", "Candidate")
        self.commit = self.git_run("rev-parse", "HEAD").stdout.strip()
        # Two independently addressable repositories both have the right main.
        for name in ("NxLibrary", "oort-nx", "nxnative"):
            self.git_run("clone", "-q", "--bare", ".", str(self.root / name))
        self.git_run("remote", "add", "origin", f"git@github.com:{PUBLIC}.git")
        self.stub(
            "git",
            """mapped() {
  case "${1%.git}" in
    https://github.com/fixture/*|git@github.com:fixture/*|ssh://git@github.com/fixture/*)
      printf '%s/%s\\n' "$FIXTURES" "${1##*/}" | sed 's/\\.git$//' ;;
    *) return 1 ;;
  esac
}
case " $* " in
  *" ls-remote "*)
    flags=()
    i=0
    for arg do
      if [[ "$arg" == --get-url ]]; then exec "$REAL_GIT" "$@"; fi
      if [[ "$arg" == --exit-code || "$arg" == --heads ]]; then flags+=("$arg"); fi
      if repo=$(mapped "$arg"); then
        shift "$i"
        shift
        exec "$REAL_GIT" ls-remote "${flags[@]}" "$repo" "$@"
      fi
      i=$((${i:-0} + 1))
    done
    exit 99 ;;
  " fetch -q origin main ")
    repo=$(mapped "$("$REAL_GIT" remote get-url origin)") || exit 99
    exec "$REAL_GIT" fetch -q "$repo" main:refs/remotes/origin/main ;;
  *" clone "*" --no-tags "*)
    flags=()
    for arg do
      if [[ "$arg" == --bare || "$arg" == --no-checkout ]]; then flags+=("$arg"); fi
    done
    while [[ "$1" != https://github.com/* ]]; do shift; done
    exec "$REAL_GIT" clone -q "${flags[@]}" --no-tags "$(mapped "$1")" "$2" ;;
  *" push "*)
    repo=$(mapped "$("$REAL_GIT" remote get-url --push origin)") || exit 99
    args=()
    for arg do
      if [[ "$arg" == origin ]]; then arg="$repo"; fi
      args+=("$arg")
    done
    exec "$REAL_GIT" "${args[@]}" ;;
  *) exec "$REAL_GIT" "$@" ;;
esac
""",
        )
        self.stub(
            "gh",
            """case "$1" in
  api)
    case "$2" in
      "repos/$CANONICAL/releases")
        [[ " $* " == *" --paginate "* ]]
        [[ "${RELEASE_LIST_FAIL:-0}" != 1 ]] || exit 90
        if [[ -f "$FIXTURES/existing-release" ]]; then cat "$FIXTURES/existing-release"; fi ;;
      *) printf '%s\\n' "$CANONICAL" ;;
    esac ;;
  release)
    [[ "$2" == create && " $* " == *" --repo github.com/$CANONICAL --verify-tag "* ]]
    "$REAL_GIT" -C "$FIXTURES/${CANONICAL#*/}" rev-parse --verify "refs/tags/$3"
    printf '%s %s\\n' "$CANONICAL" "$3" > "$FIXTURES/released" ;;
  *) echo "Unexpected GitHub write" >&2; exit 99 ;;
esac
""",
        )
        self.stub("swift", 'echo "Reached release build checks" >&2; exit 42\n')
        self.stub("codesign", ":\n")
        self.stub("ditto", 'touch "${@: -1}"\n')

    def write(self, relative, contents):
        path = self.app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + body)
        path.chmod(0o755)

    def git_run(self, *args, cwd=None):
        return subprocess.run([self.git, *args], cwd=cwd or self.app, env=self.env,
                              check=True, text=True, capture_output=True)

    def publish(self, pin=None):
        return subprocess.run(
            ["/bin/bash", "scripts/release.sh", "0.3.1", "--publish", "--notes", "notes.md",
             "--engine-repo", ENGINE, "--engine-commit", pin or self.commit],
            cwd=self.app, env=self.env, text=True, capture_output=True,
        )

    def test_rejects_another_push_repository_even_when_both_have_the_candidate(self):
        self.git_run("remote", "set-url", "--push", "origin", f"git@github.com:{OTHER}.git")
        self.assert_blocked("origin push URL")

    def test_plain_dmg_is_explicit_and_keeps_the_versioned_asset_name(self):
        self.stub("swift", ":\n")
        for flags in ([], ["--plain-dmg"]):
            result = subprocess.run(
                ["/bin/bash", "scripts/release.sh", "0.3.1", "--engine-repo", ENGINE,
                 "--engine-commit", self.commit, *flags],
                cwd=self.app, env=self.env, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.root / "dmg-args").read_text().splitlines(),
                             (["--plain"] if flags else []) + [str(self.app.resolve() / "work/release/Oort NX.app")])
            self.assertTrue((self.app / "work/release/Oort-NX-0.3.1.dmg").is_file())
        self.assertFalse((self.root / "released").exists())

    def assert_blocked(self, expected, **options):
        result = self.publish(**options)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Reached release build checks", result.stderr)
        self.assertIn(expected, result.stderr)
        self.assertEqual(self.git_run("tag", "--list").stdout, "")
        self.assertFalse((self.root / "released").exists())

    def test_rejects_multiple_push_urls(self):
        for repo in (PUBLIC, OTHER):
            self.git_run("remote", "set-url", "--add", "--push", "origin", f"git@github.com:{repo}.git")
        self.assert_blocked("origin push URL")

    def test_rejects_an_origin_push_rewrite(self):
        self.git_run("config", f"url.git@github.com:{OTHER}.git.pushInsteadOf", f"git@github.com:{PUBLIC}.git")
        self.assert_blocked("origin push URL")

    def test_uses_remote_main_not_the_local_tracking_ref(self):
        self.git_run("commit", "--allow-empty", "-qm", "Only local")
        self.git_run("update-ref", "refs/remotes/origin/main", "HEAD")
        self.assert_blocked("HEAD is not the published main")

    def test_refuses_an_existing_tag_on_the_destination(self):
        self.git_run("tag", "-a", "-m", "Already used", "v0.3.1", cwd=self.root / "NxLibrary")
        self.assert_blocked("the remote tag v0.3.1 already exists")

    def install_matching_tags(self):
        self.git_run("tag", "-a", "-m", "Fixture tag", "v0.3.1")
        self.git_run("push", str(self.root / "NxLibrary"), "refs/tags/v0.3.1")
        return self.git_run("rev-parse", "refs/tags/v0.3.1").stdout.strip()

    def test_resumes_after_pushing_the_identical_tag(self):
        tag = self.install_matching_tags()
        self.stub("swift", ":\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "released").read_text(), f"{PUBLIC} v0.3.1\n")
        for repo in (self.app, self.root / "NxLibrary"):
            self.assertEqual(self.git_run("rev-parse", "refs/tags/v0.3.1", cwd=repo).stdout.strip(), tag)

    def test_does_not_resume_with_different_tag_objects_at_the_same_commit(self):
        self.git_run("tag", "v0.3.1")
        self.git_run("tag", "-a", "-m", "Remote annotation", "v0.3.1", cwd=self.root / "NxLibrary")
        result = self.publish()
        self.assertIn("the remote tag v0.3.1 already exists", result.stderr)
        self.assertFalse((self.root / "released").exists())

    def test_does_not_resume_with_identical_tags_at_a_different_commit(self):
        self.git_run("commit", "--allow-empty", "-qm", "Not the release")
        self.install_matching_tags()
        self.git_run("update-ref", "refs/heads/main", self.commit)
        self.git_run("read-tree", self.commit)
        result = self.publish()
        self.assertIn("does not point to the expected commit", result.stderr)
        self.assertFalse((self.root / "released").exists())

    def test_does_not_resume_when_release_exists_or_cannot_be_checked(self):
        self.install_matching_tags()
        (self.root / "existing-release").write_text("v0.3.1\n")
        self.assertIn("a release for v0.3.1 already exists", self.publish().stderr)
        self.env["RELEASE_LIST_FAIL"] = "1"
        self.assertIn("could not list releases", self.publish().stderr)
        self.assertFalse((self.root / "released").exists())

    def test_refuses_dirty_tree_and_local_tag(self):
        self.write("leftover", "")
        self.assert_blocked("the working tree has changes")
        (self.app / "leftover").unlink()
        self.git_run("tag", "v0.3.1")
        result = self.publish()
        self.assertIn("the local tag v0.3.1 already exists", result.stderr)
        self.assertFalse((self.root / "released").exists())

    def test_engine_tag_alone_does_not_count_as_a_published_branch(self):
        pin = self.git_run("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "Engine tag only").stdout.strip()
        self.git_run("push", str(self.root / "nxnative"), f"{pin}:refs/tags/tag-only")
        self.assert_blocked("must be reachable from a public branch", pin=pin)

    def test_swift_checks_use_the_packaged_engine_instead_of_ambient_settings(self):
        # The packaged pin exists upstream, but not in an ambient checkout.
        pin = self.git_run("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "Engine pin").stdout.strip()
        self.git_run("push", str(self.root / "nxnative"), f"{pin}:refs/heads/tested")
        self.env.update(NX_TEST_ENGINE_REPO="/not-the-packaged-engine", NX_TEST_ENGINE_COMMIT=self.commit)
        self.stub("swift", f'''[[ "$NX_TEST_ENGINE_COMMIT" == "{pin}" ]]
"$REAL_GIT" -C "$NX_TEST_ENGINE_REPO" cat-file -e "$NX_TEST_ENGINE_COMMIT^{{commit}}"
[[ "$NX_TEST_ENGINE_REQUIRED" == 1 ]]
printf '%s' "$NX_TEST_ENGINE_REPO" > "$FIXTURES/test-engine"
''')
        result = self.publish(pin=pin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(Path((self.root / "test-engine").read_text()).exists())

    def test_rechecks_destination_after_the_build_checks(self):
        self.stub("swift", f'"$REAL_GIT" remote set-url --push origin "git@github.com:{OTHER}.git"\n')
        self.assert_blocked("origin push URL")
        self.assertEqual(self.git_run("tag", "--list", cwd=self.root / "oort-nx").stdout, "")

    def test_pushes_only_expected_tag_to_the_public_release_repository(self):
        self.stub("swift", ":\n")
        self.git_run("remote", "set-url", "--push", "origin", f"git@github.com:{PUBLIC}.git")
        self.git_run("remote", "set-url", "origin", f"git@github.com:{OTHER}.git")
        self.git_run("tag", "-a", "-m", "Must stay local", "v0.0.1")
        self.git_run("config", "push.followTags", "true")
        self.git_run("config", "tag.gpgSign", "false")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git_run("rev-parse", "refs/tags/v0.3.1", cwd=self.root / "NxLibrary").stdout.strip(),
                         self.commit)
        self.assertEqual(self.git_run("tag", "--list", cwd=self.root / "NxLibrary").stdout.strip(), "v0.3.1")
        self.assertEqual(self.git_run("tag", "--list", cwd=self.root / "oort-nx").stdout, "")
        self.assertEqual((self.root / "released").read_text(), f"{PUBLIC} v0.3.1\n")
