"""Build the installable companion mod from source and its asset bundle."""
from pathlib import Path, PurePosixPath
import json, zipfile
root=Path(__file__).resolve().parent
version=json.loads((root/'manifest.json').read_text())['version']
output=root/('PokemonCompanion-FireRed-v'+version+'.zip')
with zipfile.ZipFile(root/'assets.zip') as assets, zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as package:
    for name in ['main.lua','companion.lua','manifest.json']:
        package.write(root/name,'PokemonCompanion/'+name)
    package.write(root/'MOD-README.md','PokemonCompanion/README.md')
    for entry in assets.infolist():
        path=PurePosixPath(entry.filename)
        assert not path.is_absolute() and '..' not in path.parts and path.parts[0]=='assets'
        if not entry.is_dir(): package.writestr('PokemonCompanion/'+entry.filename,assets.read(entry))
with zipfile.ZipFile(output) as package:
    assert package.testzip() is None
print(output.name)
