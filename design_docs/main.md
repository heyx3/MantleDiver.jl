# Mantle Diver

## Setting

In 2058, humanity discovered that the Earth's Mantle is rich with minerals and states of matter which cannot be formed in the crust. Even in a lab, only small quantities can be produced. Yet these crumbs of material revolutionized science and technology with their application.

This led to a new gold rush, as every country and company on earth races to uncover and control veins of the new materials.

However, the technology for hyper-deep mining isn't there yet. Most nations have turned to fire-and-forget probes that dig straight down, launch the resources back upwards, and collapse in on themselves. Conditions are too hot and pressurized for remote control or AI-driven mining.

A new group is experimenting with a cutting-edge pod made from the mantle materials. This pod can hold a human pilot, and safely send them back up with the mined material.

You are the first human to ever explore the Earth's Mantle.


## Summary

Dig through rock, mineral veins, and whatever else can be found in the Mantle. Collect as many resources as possible before ditching the rig and taking those resources home.

Manage your pod's limited resources: storage space, hull integrity. Upgrade your pod's drill, maneuverability, sensor apparatus, and special abilities. Avoid environmental hazards through careful navigation of the mining area and your upgraded abilities.

Discover what's hiding deep within the mantle.

# Visuals

[Detailed in a separate doc](visuals.md)

# The levels

Each outing is procedurally generated -- each time you drop into the mantle, you arrive at a new destination.
The rock and minerals are organized into a 3D voxel grid.
The distribution of minerals, and shape of empty spaces between rocks, is different each time.
Each rock voxel has a specific spread of minerals;
    for example, one block may be 75% rock, 18% mineral B, and 7% mineral D.

## Hazards

The following things can appear within the mining area:

* Pressurized Lava which explodes when drilled, causing nearby rock to melt
* A flow of liquid mantle, which will push your pod along it if you move into it
* "Uber-mineral" blocks which contain many valuable materials within it
* Remnants of earlier mining pods and the paths they carved out, exposing a rich mineral vein
* Unstable rock which collapses if you sit the pod on top of it
* Hot areas with black smoke that cause gradual hull damage and obscure the physical view (but not other sensors)

As you go deeper, more interesting and dangerous things appear:

* Mysterious structures made of an extremely hard, undrillable metal
  * Outer structures are more ruined and have holes which you can get into to explore the space
* Odd mineral formations which warp space and send you to other similar formations
* Decaying material which violently explodes if drilled, carving out larger sections of rock
* Open elevator platforms that can significantly change your elevation

If you upgrade your drill enough and break through the undrillable metal structures,
    you will get to the [end-game](end-game.md) (documented elsewhere).

## Preparation

Before each outing, the player can view some information about it:

* The distribution of minerals

They can also decide on upgrades for their next pod.
Upgrades reset on every outing, so the player can build different loadouts for each mission based on their current priorities.
For more info about upgrades, see [the below section](#the-mining-pod).

The player can bank unspent materials;
    this helps prevent them from losing all their progress when a mission goes catastrophically bad.
Once they banked enough materials, they start receiving an "income"
    from the company's other miners using those materials to do missions themselves.
This creates concrete milestones for the player's progress which do not reset
    no matter how many catastrophic accidents the player has.

# The mining pod

The player can look out of the front of the pod to see the world through a transparent glass.
On the inside walls of the pod are various displays (depending on how the pod is upgraded).

Mined minerals are liquified and stored in a pressurized container in the pod, alongside the player in the return-to-surface unit.
The mineral levels are visible on one of the inside wall displays.

The pod itself will have various upgrades, which only last for one outing.
The pod's properties and upgrades are as follows:

## Storage Space

* Each type of material you can mine has its own storage slot, which compresses the material into a small pocket in the pod
* Plain rock has storage space too; once it's full you can't mine any more
* You can also upgrade the space to allow the whole thing to fit any type of material
  * This is a special upgrade requiring multiple types of materials.
* You can upgrade rock storage to vaporize the rock, removing the need to store it
  * This is a special upgrade requiring multiple types of materials.
* Upgraded with the mineral *kertil*, except as mentioned above

## Hull Integrity

* Many pod maneuvers add stress to the hull, such as fall-damage.
* Too much stress, and it starts collapsing. When this happens, the player is immediately ejected with their mined material, back to home. The mission is over.
* Can be upgraded for overall health and/or resistance to heat
* Upgraded with the material *gelstance*

## Drill

* The drill's speed depends on the material it's moving through.
* Drill speed is upgraded per-material.
  * This adds more value to the planning phase; the player has to decide which materials to prioritize based on both what they want, and what the level contains.
* Upgraded with the material "mytil"

## Specials

* **Shaped charges**: lay down some charges along consecutive spaces in the rock voxel grid, then detonate them all at once, vaporizing the rock and leaving only mineral
* **Neutrino laser**: identify mineral sources through the rock, displaying as colored rocks behind other rocks.
* **Jump jet**: launch straight upwards
* Upgraded with the mineral "silbon"

## Sensors

* Main view of the world starts black-and-white
  * You can upgrade to greyscale for better detection of minerals
  * You can upgrade it to color for *really* good detection of minerals
* You can quickly rotate the view of your vehicle in 90-degree increments.
* You can add another view which senses and displays all surrounding rock.
* You can upgrade the length, breadth, and intensity of your flashlight.
* Upgraded with the mineral "gahp"

## Maneuverability

* The basic pod can move forward/back, strafe, and drill in all 6 orthogonal directions
* Upgraded maneuvere are as follows:
    * Cross over single empty spaces, both straight ahead and around a corner
    * Climb ledges
    * General reduction in fall damage
* Upgraded with the mineral "ourin"