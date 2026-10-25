#include "register_types.h"

#include "../../extension/src/demo_battle.hpp"

// Registers DemoBattle at the same level and under the same name as the GDExtension (extension/src/register_types.cpp),
// so game/scripts/*.gd work unchanged with either build.
void initialize_tdc_demo_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    GDREGISTER_CLASS(godot::DemoBattle);
}

void uninitialize_tdc_demo_module(ModuleInitializationLevel) {}
