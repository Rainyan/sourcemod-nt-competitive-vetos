# sourcemod-nt-competitive-vetos
A SourceMod plugin for Neotokyo that introduces a map veto system for competitive play.

## Compile requirements
### SourceMod version
* 1.7 or newer
### Includes
* [SourceMod Neotokyo include](https://github.com/softashell/sourcemod-nt-include)
* [nt_competitive_vetos_enum include](scripting/include/nt_competitive_vetos_enum.inc)

## For players
### Usage
* `sm_veto` – Indicate that your team is ready for veto.
* `sm_unveto` – Cancel your team's veto readiness.
* `sm_forceveto` – Admin command. Force veto to start.
* `sm_resetveto` – Admin command. Force a veto state full reset.

As usual, you can also invoke these types of `sm_(...)` commands from the server chat, using the server's command prefix (usually "!", so `sm_veto` would turn into a chat command of `!veto`, and so forth).

The actual veto process is controlled by interactive panels using the number keys, and is fully automated.

## For server operators
### Installation
In addition to the standard .smx plugin installation, this plugin requires two additional config files to be placed in `addons/sourcemod/configs`:
* _veto.cfg_ – Config file for defining the veto map pool to be used.
* _veto_maplist.ini_ – The default map pool file, referenced by _veto.cfg_. If you're running a single veto pool, this is the file you will primarily want to edit. If you instead require multiple veto pools, you can create additional files and swap those in the _veto.cfg_ config as required.

You can find the example config files in the [configs folder](configs/) of this repo.

## For plugin devs
### Accessing veto information from another plugin

This plugin supports native calls and global forwards for accessing the live veto status. Please see the [natives and forwards prototypes](scripting/include/nt_competitive_vetos_natives.inc) for specification, and [example plugin implementation here](scripting/example_plugin_for_natives_and_forwards.sp).
