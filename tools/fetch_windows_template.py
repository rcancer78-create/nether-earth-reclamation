"""Fetch only the Windows release executable from the official templates ZIP.
HTTP byte ranges avoid downloading the unrelated platform templates (1.3 GB).
"""
import io, json, struct, urllib.request, zipfile, zlib, hashlib
from pathlib import Path

VERSION = '4.5.1-stable'
req = urllib.request.Request('https://api.github.com/repos/godotengine/godot/releases/tags/'+VERSION)
release = json.load(urllib.request.urlopen(req,timeout=30))
asset = next(a for a in release['assets'] if a['name']==f'Godot_v{VERSION}_export_templates.tpz')
req = urllib.request.Request(asset['url']+'?download=1',headers={'Accept':'application/octet-stream'})
with urllib.request.urlopen(req,timeout=30) as response:
    if 'json' in response.headers.get('Content-Type', '').lower():
        raise RuntimeError('GitHub returned asset metadata instead of the templates archive')
    url = response.url

def get_range(start,end):
    if not 0 <= start <= end < size:
        raise RuntimeError('Invalid byte range in templates archive')
    req=urllib.request.Request(url,headers={'Range':f'bytes={start}-{end}'})
    with urllib.request.urlopen(req,timeout=120) as response:
        if response.status != 206: raise RuntimeError('Server did not honor byte range')
        if response.headers.get('Content-Range') != f'bytes {start}-{end}/{size}':
            raise RuntimeError('Server returned an unexpected Content-Range')
        data=response.read()
    if len(data)!=end-start+1: raise RuntimeError('Truncated range')
    return data

size=asset['size']
if not isinstance(size, int) or size < 22:
    raise RuntimeError('GitHub reported an invalid templates archive size')
tail=get_range(max(0,size-65557),size-1)
pos=tail.rfind(b'PK\x05\x06')
if pos < 0 or len(tail)-pos < 22:
    raise RuntimeError('ZIP end-of-central-directory record is missing or truncated')
end=struct.unpack_from('<4s4H2LH',tail,pos)
if end[1] != 0 or end[2] != 0 or end[3] != end[4]:
    raise RuntimeError('Multi-volume templates archives are not supported')
if end[4] == 0xffff or end[5] == 0xffffffff or end[6] == 0xffffffff:
    raise RuntimeError('ZIP64 templates archives are not supported')
if pos+22+end[7] != len(tail):
    raise RuntimeError('ZIP end-of-central-directory comment length is invalid')
cd_size,cd_offset=end[5],end[6]
if cd_size <= 0 or cd_offset+cd_size > size:
    raise RuntimeError('ZIP central-directory bounds are invalid')
directory=get_range(cd_offset,cd_offset+cd_size-1)
entries=[]
pos=0
while directory[pos:pos+4]==b'PK\x01\x02':
    if pos+46 > len(directory):
        raise RuntimeError('ZIP central-directory entry is truncated')
    fields=struct.unpack_from('<4s6H3L5H2L',directory,pos)
    name_len,extra_len,comment_len=fields[10:13]
    if pos+46+name_len+extra_len+comment_len > len(directory):
        raise RuntimeError('ZIP central-directory filename or metadata is truncated')
    name=directory[pos+46:pos+46+name_len].decode()
    if name.endswith('windows_release_x86_64.exe'):
        entries.append((name,fields[4],fields[7],fields[8],fields[9],fields[16]))
    pos+=46+name_len+extra_len+comment_len
for name,method,crc,compressed,uncompressed,offset in entries:
    header=get_range(offset,offset+29)
    fields=struct.unpack('<4s5H3L2H',header)
    if fields[0] != b'PK\x03\x04' or fields[3] != method:
        raise RuntimeError('Windows template has an invalid ZIP local header')
    if method not in (0,8):
        raise RuntimeError(f'Unsupported ZIP compression method: {method}')
    start=offset+30+fields[-2]+fields[-1]
    print('Downloading',name,compressed,'bytes',flush=True)
    data=get_range(start,start+compressed-1)
    data=zlib.decompress(data,-15) if method==8 else data
    if len(data) != uncompressed:
        raise RuntimeError('Windows template uncompressed size does not match ZIP metadata')
    if zlib.crc32(data) != crc:
        raise RuntimeError('Windows template CRC32 does not match ZIP metadata')
    dest=Path('.tools/templates/windows_release_x86_64.exe')
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_bytes(data)
    print('Verified CRC32; SHA256',hashlib.sha256(data).hexdigest(),flush=True)
if not entries: raise RuntimeError('Windows template missing in official archive')
