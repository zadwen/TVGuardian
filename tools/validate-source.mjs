// Optional grammar/project validation on non-macOS hosts. This is not Swift
// compilation. Install the documented QA-only packages under .build/qa first.
import { createRequire } from 'node:module';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const requireQA = createRequire(resolve(root, '.build/qa/package.json'));
const xcode = requireQA('xcode');
const project = xcode.project(resolve(root, 'ios/TVGuardian.xcodeproj/project.pbxproj'));
project.parseSync();
const targets = Object.values(project.hash.project.objects.PBXNativeTarget).filter(v => typeof v === 'object');
if (targets.length !== 3) throw new Error('Expected app, unit test and UI test targets.');
console.log(`PBX project parsed: ${targets.length} native targets.`);
const { Parser, Language } = requireQA('web-tree-sitter');
await Parser.init();
const language = await Language.load(resolve(root, '.build/qa/node_modules/tree-sitter-wasms/out/tree-sitter-swift.wasm'));
const parser = new Parser(); parser.setLanguage(language);
const all = (await readdir(resolve(root,'ios'), { recursive:true })).filter(name => name.endsWith('.swift'));
let errors = 0;
for (const name of all) {
  const source = await readFile(resolve(root,'ios',name),'utf8');
  const tree = parser.parse(source);
  if (!tree.rootNode.hasError) continue;
  function inspect(node) {
    if (node.type === 'ERROR' || node.isMissing) {
      console.error(`${name}:${node.startPosition.row + 1}:${node.startPosition.column + 1} ${node.type}: ${node.text.slice(0,160)}`); errors++; return;
    }
    for (const child of node.children) if (child.hasError || child.isMissing) inspect(child);
  }
  inspect(tree.rootNode);
}
console.log(`Swift grammar parsed: ${all.length} files; ${errors} syntax errors. Type checking and Apple SDK validation require Xcode.`);
let cloudErrors = 0;
const YAML = requireQA('yaml');
for (const name of ['.github/workflows/verify.yml', '.github/workflows/build-iphone.yml']) {
  const document = YAML.parseDocument(await readFile(resolve(root,name),'utf8'));
  for (const error of document.errors) { console.error(`${name}: ${error.message}`); cloudErrors++; }
}
console.log(`Cloud workflow YAML parsed: 2 files; ${cloudErrors} syntax errors. Bash syntax and Xcode compilation are checked on the Mac runner.`);
errors += cloudErrors;
if (errors) process.exitCode = 1;
