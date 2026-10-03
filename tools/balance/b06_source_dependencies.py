"""Conservative reachable-source closure for the B06 live-scene harness.
No docs or unrelated test files are dependencies. Class-name references and
literal res:// references are transitive, including every JSON path supplied to
ContentRegistry and chapter registries. Unreferenced candidate JSON is not loaded.
This is not asset pixel QA.
"""
import hashlib,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE_SUFFIXES={'.gd','.tscn','.tres','.gdshader','.json'}
def fingerprint():
 classes={}
 for f in [*ROOT.glob('scripts/**/*.gd'),*ROOT.glob('config/*.gd')]:
  m=re.search(r'^class_name\s+(\w+)',f.read_text(),re.M)
  if m:classes[m.group(1)]=f
 project=ROOT/'project.godot';text=project.read_text();auto=text.split('[autoload]',1)[1].split('\n[',1)[0] if '[autoload]' in text else ''
 queue=[ROOT/'tests/test_b06_balance_matrix.tscn',*[ROOT/x for x in re.findall(r'res://([^"\s]+)',auto)]]
 included={project,ROOT/'tools/test_workspace.py',pathlib.Path(__file__).resolve(),ROOT/'tools/balance/run_b06_baseline.py',ROOT/'tools/balance/run_b06_policy_probe.py'}
 while queue:
  f=queue.pop()
  if f in included or not f.is_file():continue
  included.add(f);body=f.read_text()
  for ref in re.findall(r'res://([^"\s\)]+)',body):
   p=ROOT/ref
   if p.suffix in SOURCE_SUFFIXES and p.is_file():queue.append(p)
  if f.suffix=='.gd':
   tokens=set(re.findall(r'\b[A-Za-z_]\w*\b',body))
   queue.extend(p for name,p in classes.items() if name in tokens)
 return {str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(included)}
