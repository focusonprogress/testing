import os, glob, xml.dom.minidom
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref=[0]
def nref():
    ref[0]+=1; return "RBX%08X"%ref[0]
def script(path):
    name=os.path.basename(path)
    if name.endswith('.server.lua'): cls='Script'; name=name[:-11]
    elif name.endswith('.client.lua'): cls='LocalScript'; name=name[:-11]
    else: cls='ModuleScript'; name=name[:-4]
    src=open(path,encoding='utf-8').read()
    assert ']]>' not in src
    return f'<Item class="{cls}" referent="{nref()}"><Properties><string name="Name">{name}</string><ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString></Properties></Item>'
def folder(name, items):
    return f'<Item class="Folder" referent="{nref()}"><Properties><string name="Name">{name}</string></Properties>{"".join(items)}</Item>'
def write(fn, items):
    doc='<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'+"".join(items)+'</roblox>'
    xml.dom.minidom.parseString(doc.encode())  # valida o XML
    open(os.path.join(root,'build',fn),'w',encoding='utf-8').write(doc)
    print(fn, len(doc))
files=lambda d: sorted(glob.glob(os.path.join(root,'src',d,'*.lua')))
write('1_Shared_ReplicatedStorage.rbxmx',[folder('Shared',[script(f) for f in files('ReplicatedStorage/Shared')])])
write('2_Progression_ServerScriptService.rbxmx',[folder('Progression',[script(f) for f in files('ServerScriptService/Progression')])])
write('3_StarterPlayerScripts.rbxmx',[script(f) for f in files('StarterPlayer/StarterPlayerScripts')])
