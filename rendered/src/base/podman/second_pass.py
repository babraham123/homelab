# jinjanate --customize hooks for the second pass, the render on the node of a *.j2.j2
# template's remaining Jinja (render_secrets.sh, render_services.sh). It uses square
# brackets, [[ var ]] and [% block %], so the first pass on the workstation leaves it as
# text, and so a {{ }} that survives the first pass, say an app's own Go template, is
# left alone here.
# Ref: https://github.com/kpfleming/jinjanator#customization


def j2_environment_params():
  return {
    "variable_start_string": "[[",
    "variable_end_string": "]]",
    "block_start_string": "[%",
    "block_end_string": "%]",
    "comment_start_string": "[#",
    "comment_end_string": "#]",
  }
