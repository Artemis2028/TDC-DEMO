class_name Version
## The demo's version, shown on the menu, in the HUD's top-left corner and in the window title, so a screenshot or a
## bug report says which build it came from.
## NUMBER is raised by hand: the middle number for a build with new features, the last for fixes only.
## BUILD is stamped by the CI build (.github/workflows/build.yml): the run number and the commit. "dev" means a
## local, unstamped build.

const NUMBER := "0.8.0"
const BUILD := "dev"

## "v0.8.0 · build 52 (68ab2ea)", or "v0.8.0 · dev" for a local build.
static func text() -> String:
	return "v%s · %s" % [NUMBER, BUILD if BUILD == "dev" else "build " + BUILD]
