{ components, ... }:
{
  imports = [
    (components + /tool/git)
    (components + /tool/ssh)
    (components + /tool/syncthing)
  ];
}
