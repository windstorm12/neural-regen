@tool
extends EditorPlugin

func _enter_tree():
    # Register the custom node
    # Name, Parent Type, Script, Icon (null for default)
    add_custom_type(
        "SelfHealingCreature", 
        "Node2D", 
        preload("self_healing_node.gd"), 
        null
    )

func _exit_tree():
    # Clean up
    remove_custom_type("SelfHealingCreature")