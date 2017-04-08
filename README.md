Shack (PLEASE IGNORE)
=====================

These are the first scraps of code pulled together from former
projects into a prototype shack controller for RemoteRadio
implemented in Elixir/Nerves.   

Previous projects were implemented in Python

## Current Status

Noting worth seeing here yet, I'm just getting some old code put together.

It likely doesn't even compile yet.

## Command Protocol Types

ASCII commands followed by semicolon (kenwood convention)

Kenwood
Elecraft
Yaesu (recent models)
DZKit
Flex

  A device consists of a set of properties
  A device exposes attributes
  A device has settings

  Change the volume property to 35
  Change the volume attribute to 335
  Change the frequency setting to 14.302.10


## Terminology

* Frame - A packet sent to a device to control it or received from a device
* Field - A property or attribute of a device that can be controlled of changes
