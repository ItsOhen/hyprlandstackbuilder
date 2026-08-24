Builds a contained hyprland -git stack.

Does not pollute system libraries.

Mostly used for testing.

Build will end up in install/ if -DINSTALL_DIR isn't set.

Can do specific PR checkouts. Just slap the package and the PR number onto it.

`make AQUAMARINE=1234` for PR 1234.

If you want to use the packages for everyday use, consider adding the install/bin/ path to PATH.

You know what.. Just run make help and it will tell you. Or read the cmake file.
