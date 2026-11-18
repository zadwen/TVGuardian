// Deterministic, dependency-free Xcode project writer. The generated project is
// committed and opens directly; this script is needed only when adding files.
import { readdir, writeFile, mkdir } from 'node:fs/promises';
import { resolve, relative, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = fileURLToPath(new URL('../', import.meta.url));
const ios = resolve(root, 'ios');
const id = value => createHash('sha256').update(value).digest('hex').slice(0, 24).toUpperCase();
const quote = value => JSON.stringify(value);
async function files(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = join(directory, entry.name);
    if (entry.isDirectory()) { if (!entry.name.endsWith('.xcassets')) result.push(...await files(full)); }
    else if (entry.name.endsWith('.swift')) result.push(relative(ios, full).replaceAll('\\', '/'));
  }
  return result.sort();
}
const appFiles = await files(resolve(ios, 'TVGuardian'));
const testFiles = await files(resolve(ios, 'TVGuardianTests'));
const uiTestFiles = await files(resolve(ios, 'TVGuardianUITests'));
const resources = ['TVGuardian/Assets.xcassets', 'TVGuardian/PrivacyInfo.xcprivacy'];
const objects = [];
const object = (name, content) => { objects.push(`${id(name)} = { ${content} };`); return id(name); };
const list = values => '(' + values.map(value => value + ',').join(' ') + ')';
const refs = [];
for (const file of [...appFiles, ...testFiles, ...uiTestFiles, ...resources, 'TVGuardian/Info.plist']) {
  const type = file.endsWith('.swift') ? 'sourcecode.swift' : file.endsWith('.xcassets') ? 'folder.assetcatalog' : file.endsWith('.xcprivacy') ? 'text.xml' : 'text.plist.xml';
  refs.push(object('file:' + file, `isa = PBXFileReference; lastKnownFileType = ${quote(type)}; path = ${quote(file)}; sourceTree = "<group>";`));
  if (!file.endsWith('Info.plist')) object('build:' + file, `isa = PBXBuildFile; fileRef = ${id('file:' + file)};`);
}
object('product:app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TVGuardian.app; sourceTree = BUILT_PRODUCTS_DIR;');
object('product:test', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TVGuardianTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
object('product:uitest', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TVGuardianUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
object('group:products', `isa = PBXGroup; children = ${list([id('product:app'), id('product:test'), id('product:uitest')])}; name = Products; sourceTree = "<group>";`);
object('group:main', `isa = PBXGroup; children = ${list([...refs, id('group:products')])}; sourceTree = "<group>";`);
for (const target of ['app', 'test', 'uitest']) {
  const sourceFiles = target === 'app' ? appFiles : target === 'test' ? testFiles : uiTestFiles;
  object(target + ':sources', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ${list(sourceFiles.map(file => id('build:' + file)))}; runOnlyForDeploymentPostprocessing = 0;`);
  object(target + ':resources', `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ${list(target === 'app' ? resources.map(file => id('build:' + file)) : [])}; runOnlyForDeploymentPostprocessing = 0;`);
  object(target + ':frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
}
object('proxy:app', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('target:app')}; remoteInfo = TVGuardian;`);
object('dependency:app', `isa = PBXTargetDependency; target = ${id('target:app')}; targetProxy = ${id('proxy:app')};`);
for (const scope of ['project', 'app', 'test', 'uitest']) {
  for (const mode of ['Debug', 'Release']) {
    let settings = `IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; `;
    settings += mode === 'Debug' ? 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ' : 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; VALIDATE_PRODUCT = YES; ';
    if (scope !== 'project') settings += `PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ""; CURRENT_PROJECT_VERSION = 2; MARKETING_VERSION = 0.1.1; `;
    if (scope === 'app') settings += 'PRODUCT_BUNDLE_IDENTIFIER = com.example.TVGuardian; INFOPLIST_FILE = TVGuardian/Info.plist; GENERATE_INFOPLIST_FILE = NO; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; ';
    if (scope === 'test') settings += 'PRODUCT_BUNDLE_IDENTIFIER = com.example.TVGuardianTests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/TVGuardian.app/TVGuardian"; BUNDLE_LOADER = "$(TEST_HOST)"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"; ';
    if (scope === 'uitest') settings += 'PRODUCT_BUNDLE_IDENTIFIER = com.example.TVGuardianUITests; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = TVGuardian; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"; ';
    object('config:' + scope + ':' + mode, `isa = XCBuildConfiguration; buildSettings = { ${settings} }; name = ${mode};`);
  }
  object('configs:' + scope, `isa = XCConfigurationList; buildConfigurations = ${list(['Debug', 'Release'].map(mode => id('config:' + scope + ':' + mode)))}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
for (const target of ['app', 'test', 'uitest']) {
  const name = target === 'app' ? 'TVGuardian' : target === 'test' ? 'TVGuardianTests' : 'TVGuardianUITests';
  const type = target === 'app' ? 'com.apple.product-type.application' : target === 'test' ? 'com.apple.product-type.bundle.unit-test' : 'com.apple.product-type.bundle.ui-testing';
  object('target:' + target, `isa = PBXNativeTarget; buildConfigurationList = ${id('configs:' + target)}; buildPhases = ${list(['sources', 'frameworks', 'resources'].map(phase => id(target + ':' + phase)))}; buildRules = (); dependencies = ${list(target !== 'app' ? [id('dependency:app')] : [])}; name = ${name}; productName = ${name}; productReference = ${id('product:' + target)}; productType = ${quote(type)};`);
}
object('project', `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = { ${id('target:app')} = { CreatedOnToolsVersion = 16.0; }; ${id('target:test')} = { CreatedOnToolsVersion = 16.0; TestTargetID = ${id('target:app')}; }; ${id('target:uitest')} = { CreatedOnToolsVersion = 16.0; TestTargetID = ${id('target:app')}; }; }; }; buildConfigurationList = ${id('configs:project')}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = ${id('group:main')}; productRefGroup = ${id('group:products')}; projectDirPath = ""; projectRoot = ""; targets = ${list([id('target:app'), id('target:test'), id('target:uitest')])};`);
const project = resolve(ios, 'TVGuardian.xcodeproj');
await mkdir(resolve(project, 'xcshareddata/xcschemes'), { recursive: true });
const sections = new Map();
for (const entry of objects) {
  const type = entry.match(/isa = (\w+);/)[1];
  if (!sections.has(type)) sections.set(type, []);
  sections.get(type).push(entry);
}
const body = [...sections.entries()].sort(([a],[b]) => a.localeCompare(b)).map(([type, entries]) => `/* Begin ${type} section */\n${entries.join('\n')}\n/* End ${type} section */`).join('\n');
await writeFile(resolve(project, 'project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${body}\n}; rootObject = ${id('project')}; }\n`);
await writeFile(resolve(project, 'xcshareddata/xcschemes/TVGuardian.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:app')}" BuildableName="TVGuardian.app" BlueprintName="TVGuardian" ReferencedContainer="container:TVGuardian.xcodeproj"/></BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:test')}" BuildableName="TVGuardianTests.xctest" BlueprintName="TVGuardianTests" ReferencedContainer="container:TVGuardian.xcodeproj"/></TestableReference><TestableReference skipped="NO" parallelizable="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:uitest')}" BuildableName="TVGuardianUITests.xctest" BlueprintName="TVGuardianUITests" ReferencedContainer="container:TVGuardian.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:app')}" BuildableName="TVGuardian.app" BlueprintName="TVGuardian" ReferencedContainer="container:TVGuardian.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:app')}" BuildableName="TVGuardian.app" BlueprintName="TVGuardian" ReferencedContainer="container:TVGuardian.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`);
console.log(`Generated project with ${appFiles.length} application, ${testFiles.length} unit test and ${uiTestFiles.length} UI test source files.`);
