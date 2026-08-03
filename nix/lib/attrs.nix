{ lib }:
rec {
  hasNonEmptyString =
    attrs: key:
    builtins.hasAttr key attrs
    && builtins.isString attrs.${key}
    && attrs.${key} != "";

  hasPositiveInt =
    attrs: key:
    builtins.hasAttr key attrs
    && builtins.isInt attrs.${key}
    && attrs.${key} > 0;

  mapNamesToAttrs =
    names: mkValue:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = mkValue name;
        })
        names
    );

  mergeRecursiveAttrsList = attrsList: lib.foldl' lib.recursiveUpdate { } attrsList;

  mergeAttrFromList =
    attrName: attrsList:
    mergeRecursiveAttrsList (map (it: it.${attrName} or { }) attrsList);

  mergeAttrFromListWithExtra =
    attrName: attrsList: extraAttrs:
    mergeRecursiveAttrsList (
      (map (it: it.${attrName} or { }) attrsList)
      ++ extraAttrs
    );

  importIfExists = path: args: if builtins.pathExists path then import path args else { };

  mkHostDataEntry =
    { configAttrName
    , hostSystemAttr
    , hostCtx
    , hostChecks ? { }
    }:
    {
      ${configAttrName}.${hostCtx.name} = hostCtx.${hostSystemAttr};
      checks.${hostCtx.system} = hostChecks;
      mainUsers.${hostCtx.name} = hostCtx.mainUser;
    };

  specsToAttrs =
    specs: mkValue:
    builtins.listToAttrs (
      map
        (spec: {
          inherit (spec) name;
          value = mkValue spec;
        })
        specs
    );
}
