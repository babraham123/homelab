# shellcheck shell=bash
# The passing case against the real repo: a full render of vars.template.yml, which runs
# tools/check_rendered.sh on the real inventory, scripts and routes.
# shellcheck source=tests/lib.sh
source tests/lib.sh

test_template_render_passes_checks() {
  # A copy, so the render reads vars.template.yml rather than a personal vars.yml
  rsync -a --exclude /.git --exclude /.claude --exclude /.scratch --exclude /rendered \
    --exclude /vars.yml ./ "${tmp}/repo/"
  cp vars.template.yml "${tmp}/repo/vars.yml"
  out=$(cd "${tmp}/repo" && tools/render_src.sh "${tmp}/homelab-rendered" 2>&1) || flunk "$out"
  [ ! -e "${tmp}/homelab-rendered/tests" ] || flunk "tests/ was rendered"
}
