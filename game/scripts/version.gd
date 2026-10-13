class_name Version
## The demo's version, shown on the menu, in the HUD's top-left corner and in the window title, so a screenshot or a
## bug report says which build it came from.
## NUMBER is raised by hand: the middle number for a build with new features, the last for fixes only.
## BUILD is stamped by the CI build (.github/workflows/build.yml): the run number and the commit. "dev" means a
## local, unstamped build.

const NUMBER := "0.11.0"
const BUILD := "dev"

## "v0.9.0 · build 54 (1a2b3c4)", or "v0.9.0 · dev" for a local build.
static func text() -> String:
	return "v%s · %s" % [NUMBER, BUILD if BUILD == "dev" else "build " + BUILD]
