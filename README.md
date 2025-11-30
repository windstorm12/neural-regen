# NeuralRegen: GPU-Accelerated Biological Sprites for Godot 4

**Turn any static sprite into a self-regenerating organism.**

NeuralRegen is a Godot 4 plugin that uses **Neural Cellular Automata (NCA)** running entirely on the GPU via **Compute Shaders**. It allows you to create destructible, self-healing materials with **zero CPU overhead**.

## The Tech (Why use this?)
Most "destructible terrain" scripts run on the CPU and kill performance. **NeuralRegen runs 100% on the GPU (RenderingDevice).**

*   **Zero CPU Cost:** Your game logic runs free while the GPU handles the biology.
*   **Universal:** Drag & Drop **ANY** texture (Pixel Art, High-Res, Noise). It learns the shape instantly.
*   **Two Visualization Modes:** 
    *   **Pixel Mode:** Nanobot-style digital reconstruction (Great for Cyberpunk/Retro).
    *   **Organic Mode:** Flesh/liquid healing with distortion shaders (Great for Horror/Sci-Fi).
*   **Hackable:** The logic is just GLSL. You can modify the biology.

## Installation
1. Download this repo.
2. Copy the `addons/self_healing_creature` folder into your Godot project's `addons/` folder.
3. Go to **Project -> Project Settings -> Plugins** and enable **SelfHealingCreature**.
4. Restart Godot (sometimes required for new shaders to compile).

## Quick Start
1. Add a `SelfHealingCreature` node to your scene (instead of a Sprite2D).
2. In the Inspector, drag your sprite into the **Target Texture** slot.
3. **Run the Game.**
4. **Right-Click & Drag** on the sprite to damage it and watch it heal.

## API & Scripting
You can damage the entity from any script (Bullets, Swords, Lasers) using the public API.

    # Example: A Bullet Script
    func _on_collision(body):
        if body.has_method("apply_damage"):
            # Hit at global position with a radius of 5.0 pixels
            body.apply_damage(global_position, 5.0)

## Advanced: Hacking the Engine
This plugin is not a "Black Box." It is an open-source foundation for GPU simulation.

*   **Want Square Damage?** Open `addons/self_healing_creature/shaders/nca.glsl` and change the distance check.
*   **Want Faster Growth?** Tweak the `growth_speed` multiplier in `self_healing_node.gd`.
*   **Want New Visuals?** Edit `shaders/display_mask.gdshader` to change how the "Guts" look.

You have full access to the **Compute Pipeline**.

## The Research
This plugin runs a Convolutional Neural Network (CNN) that was trained to "grow" shapes. 
The training code (Python/PyTorch) and the research behind the weights can be found in my research repo:
**https://github.com/windstorm12/neural-CA-Automata**

## License
**MIT License**. You are free to use this in commercial projects, modify it, and sell games made with it.
Created by **Windstorm**.
