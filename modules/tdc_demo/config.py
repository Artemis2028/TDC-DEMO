# The demo's rules bridge (DemoBattle) built into the engine, so the exported game is one executable.
# Build the export templates with: scons target=template_release custom_modules=<this repo>/modules


def can_build(env, platform):
    return True


def configure(env):
    pass
