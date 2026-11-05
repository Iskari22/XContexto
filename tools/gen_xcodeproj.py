#!/usr/bin/env python3
"""Genera Apps/XContexto.xcodeproj (macOS + iOS + extensión de Compartir) sin herramientas externas.

Usa carpetas sincronizadas (Xcode 16+): cualquier .swift que añadas en Apps/macOS, Apps/iOS o
Apps/ShareExtension entra solo en su target. Vuelve a ejecutarlo si cambias targets o ajustes:
    python3 tools/gen_xcodeproj.py [--team TU_TEAM_ID]
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Apps", "XContexto.xcodeproj")
TEAM = sys.argv[sys.argv.index("--team") + 1] if "--team" in sys.argv else ""


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


objects = {}


def add(_key, isa, **props):
    i = oid(_key)
    objects[i] = dict(isa=isa, **props)
    return i


def q(v):
    if isinstance(v, str):
        if v and all(c.isalnum() or c in "._/$()" for c in v) and not v[0].isdigit():
            return v
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "(" + "".join(q(x) + ", " for x in v) + ")"
    if isinstance(v, dict):
        return "{" + "".join(f"{q(k)} = {q(x)}; " for k, x in v.items()) + "}"
    return str(v)


COMMON = {
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": TEAM,
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "0.1.0",
    "GENERATE_INFOPLIST_FILE": "YES",
    "SWIFT_VERSION": "6.0",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "XContexto",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}

TARGETS = [
    dict(name="XContexto-macOS", folder="macOS", product="XContexto", ptype="com.apple.product-type.application", ext="app",
         settings={
             "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "PRODUCT_NAME": "XContexto",
             "PRODUCT_BUNDLE_IDENTIFIER": "com.xcontexto.mac", "INFOPLIST_FILE": "Config/macOS-Info.plist",
             "CODE_SIGN_ENTITLEMENTS": "Config/macOS.entitlements", "ENABLE_HARDENED_RUNTIME": "YES",
             "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.news", "COMBINE_HIDPI_IMAGES": "YES",
             "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
         }),
    dict(name="XContextoShare", folder="ShareExtension", product="XContextoShare", ptype="com.apple.product-type.app-extension", ext="appex",
         settings={
             "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1,2",
             "PRODUCT_NAME": "XContextoShare", "PRODUCT_BUNDLE_IDENTIFIER": "com.xcontexto.ios.share",
             "INFOPLIST_FILE": "Config/Share-Info.plist", "CODE_SIGN_ENTITLEMENTS": "Config/Share.entitlements",
             "SKIP_INSTALL": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "XContexto",
             "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
         }),
    dict(name="XContexto-iOS", folder="iOS", product="XContexto", ptype="com.apple.product-type.application", ext="app",
         embed="XContextoShare",
         settings={
             "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1,2",
             "PRODUCT_NAME": "XContexto", "PRODUCT_BUNDLE_IDENTIFIER": "com.xcontexto.ios",
             "INFOPLIST_FILE": "Config/iOS-Info.plist", "CODE_SIGN_ENTITLEMENTS": "Config/iOS.entitlements",
             "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
             "INFOPLIST_KEY_NSFaceIDUsageDescription": "Para que nadie más pueda abrir XContexto en tu iPhone.",
             "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
             "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
         }),
]

pkg = add("pkg", "XCLocalSwiftPackageReference", relativePath="..")

products_children, main_children, target_ids, product_refs = [], [], {}, {}

for t in TARGETS:
    n = t["name"]
    pref = add(n + ".product", "PBXFileReference", explicitFileType=("wrapper.application" if t["ext"] == "app" else "wrapper.app-extension"),
               includeInIndex="0", path=f'{t["product"]}.{t["ext"]}', sourceTree="BUILT_PRODUCTS_DIR")
    product_refs[n] = pref
    products_children.append(pref)
    group = add(n + ".group", "PBXFileSystemSynchronizedRootGroup", path=t["folder"], sourceTree="<group>")
    main_children.append(group)

    dep = add(n + ".pkgdep", "XCSwiftPackageProductDependency", package=pkg, productName="XContextoKit")
    fw_file = add(n + ".fwfile", "PBXBuildFile", productRef=dep)
    phases = [
        add(n + ".sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
        add(n + ".frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[fw_file], runOnlyForDeploymentPostprocessing="0"),
        add(n + ".resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
    ]
    deps = []
    if "embed" in t:
        e = t["embed"]
        embed_file = add(n + ".embedfile", "PBXBuildFile", fileRef=product_refs[e], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(add(n + ".embed", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="", dstSubfolderSpec="13",
                          files=[embed_file], name="Embed Foundation Extensions", runOnlyForDeploymentPostprocessing="0"))
        proxy = add(n + ".proxy", "PBXContainerItemProxy", containerPortal=oid("project"), proxyType="1",
                    remoteGlobalIDString=target_ids[e], remoteInfo=e)
        deps.append(add(n + ".targetdep", "PBXTargetDependency", target=target_ids[e], targetProxy=proxy))

    cfgs = []
    for c in ("Debug", "Release"):
        s = dict(COMMON)
        s.update(t["settings"])
        if c == "Debug":
            s.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"})
        cfgs.append(add(f"{n}.{c}", "XCBuildConfiguration", buildSettings=s, name=c))
    cl = add(n + ".cfglist", "XCConfigurationList", buildConfigurations=cfgs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
    target_ids[n] = add(n, "PBXNativeTarget", buildConfigurationList=cl, buildPhases=phases, buildRules=[], dependencies=deps,
                        fileSystemSynchronizedGroups=[group], name=n, packageProductDependencies=[dep],
                        productName=t["product"], productReference=pref, productType=t["ptype"])

products = add("products", "PBXGroup", children=products_children, name="Products", sourceTree="<group>")
config_group = add("configgroup", "PBXGroup", children=[], path="Config", sourceTree="<group>")
main = add("main", "PBXGroup", children=main_children + [config_group, products], sourceTree="<group>")

proj_cfgs = []
for c in ("Debug", "Release"):
    s = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
         "SWIFT_VERSION": "6.0", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}
    if c == "Debug":
        s.update({"ONLY_ACTIVE_ARCH": "YES", "ENABLE_TESTABILITY": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf"})
    proj_cfgs.append(add("project." + c, "XCBuildConfiguration", buildSettings=s, name=c))
proj_cl = add("project.cfglist", "XCConfigurationList", buildConfigurations=proj_cfgs, defaultConfigurationIsVisible="0",
              defaultConfigurationName="Release")

objects[oid("project")] = dict(
    isa="PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "1", "LastSwiftUpdateCheck": "2700", "LastUpgradeCheck": "2700"},
    buildConfigurationList=proj_cl, developmentRegion="es", hasScannedForEncodings="0", knownRegions=["es", "en", "Base"],
    mainGroup=main, minimizedProjectReferenceProxies="1", packageReferences=[pkg], preferredProjectObjectVersion="77",
    productRefGroup=products, projectDirPath="", projectRoot="", targets=[target_ids[t["name"]] for t in TARGETS],
)

lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {"]
for i, o in sorted(objects.items(), key=lambda kv: (kv[1]["isa"], kv[0])):
    body = "".join(f"{q(k)} = {q(v)}; " for k, v in o.items())
    lines.append(f"\t\t{i} = {{{body}}};")
lines += ["\t};", f"\trootObject = {oid('project')};", "}", ""]

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines))
print("Generado", OUT, "equipo:", TEAM or "(sin equipo: firma desactivada hasta que lo pongas)")
