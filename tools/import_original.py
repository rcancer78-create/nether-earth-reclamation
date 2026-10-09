"""Extract map tables from Santiago Ontanon's annotated Z80 disassembly.
Run: python tools/import_original.py research/disassembly/netherearth-annotated.asm
No ROM, music, sprites or executable code are included in the game.
"""
import json, re, sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding='utf-8-sig')
def table(label):
    tail = source.split(label + ':', 1)[1]
    rows = []
    for line in tail.splitlines()[1:]:
        if re.match(r'\w+:', line): break
        code = line.split(';')[0].strip()
        if code.startswith('db '):
            row = [int(v.strip().replace('#', '0x'), 0) for v in code[3:].split(',')]
            rows.append(row)
    return rows

complex_names = ['Lbfb2_warbase','Lbfe2_factory','Lbff4','Lc018','Lc03c','Lc048','Lc054','Lc060','Lc06c','Lc078','Lc084']
elements = []
def add(kind,x,y):
    if kind >= 128:
        for k,dx,dy in table(complex_names[kind & 127]):
            if k: elements.append([k,x,y])
            if dx == dy == 0: break
            x += dx if dx < 128 else dx-256
            y += dy if dy < 128 else dy-256
    else: elements.append([kind,x,y])

for label,offset in [('Lbda9_map_elements_part1',0),('Lbe79_map_elements_part2',256)]:
    for row in table(label):
        if len(row)==3: add(row[0], row[1]+offset, row[2])

buildings = []
for label,offset in [('Lbf46_warbases_factories_part1',0),('Lbf6e_warbases_factories_part2',256)]:
    for row in table(label):
        if len(row)!=3: continue
        kind,x,y=row; x+=offset
        buildings.append({'kind':kind,'x':x,'y':y,'owner':(0 if x==22 else 1) if kind==0 else -1})

out={'id':'original','title':'00 / NETHER EARTH','subtitle':'Оригинальный театр войны · 512 × 16',
     'briefing':'Последняя человеческая база держится у западной границы. Инсигниане контролируют три военных комплекса. Собирайте роботов, захватывайте промышленность и освободите Землю. Здесь действуют исходные цены, ресурсы и длительность захвата.',
     'debrief':'Четыре базы под единым командованием. В глубине коры обнаружен источник сигнала. Война за поверхность окончена — экспедиция только начинается.',
     'width':512,'height':16,'seed':1987,'resources':20,'ai':'classic','capture_ticks':144,'day_ticks':288,
     'buildings':buildings,'elements':elements,'obstacles':[],'starting_robots':[], 'next':'breach'}
Path('data/maps').mkdir(parents=True,exist_ok=True)
Path('data/maps/original.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
print(f'Original map: {len(buildings)} buildings, {len(elements)} terrain elements')

chapters = [
 ('breach','01 / ПЕРВЫЙ РАЗЛОМ','Пепельный рубеж',96,32,42,'tactician',
  'Год 2137. Разведывательный корабль «Кестрел» перехватил сигнал из-под поверхности. Захватите промышленный коридор и базу на востоке. Нейтральные заводы дают модули; военные базы — общие ресурсы. Начните с ракетного завода рядом с плацдармом.',
  'Коридор открыт. В заводских архивах найден маршрут к северному ретранслятору. Голос в эфире впервые произносит человеческое имя.', 'relay'),
 ('relay','02 / СЛЕПОЕ НЕБО','Северный ретранслятор',128,40,71,'tactician',
  'Ретранслятор управляет промышленной сетью Инсигниан. Два укреплённых узла прикрывают его подступы. Враг научился защищать базы и перебрасывать отряды. Захватите обе базы; электроника и антиграв дадут преимущество на пересечённой местности.',
  'Сигнал оказался архивом сознаний. Инсигниане охраняют не оружие, а собственную память. Но автоматический протокол уничтожения уже запущен.', 'core'),
 ('core','03 / СЕРДЦЕ ПОД ЗЕМЛЁЙ','Последний протокол',160,40,108,'siege',
  'Три управляющих ядра запускают протокол выжигания поверхности. Тяжёлые отряды и ядерные носители идут к нашему плацдарму. Захватите базы, чтобы сохранить архив, или уничтожьте их ядерными зарядами. Выбор определит последний рапорт.',
  'Протокол остановлен. Над разломом впервые за десятилетия виден чистый рассвет. Будущее зависит от того, какие голоса пережили эту войну.', '')]
for n,(ident,title,subtitle,w,h,seed,ai,brief,debrief,nxt) in enumerate(chapters):
    import random
    rng=random.Random(seed)
    bases=[{'kind':0,'x':10,'y':h//2,'owner':0}]
    for k in range(n+1): bases.append({'kind':0,'x':w-12-k*20,'y':h//2+(6 if k%2 else -3),'owner':1})
    factories=[{'kind':(i%6)+1,'x':22+i*int((w-40)/8),'y':6+(i%3)*9,'owner':-1} for i in range(9)]
    factories[0]['kind']=4
    blocks=[]
    for i in range(w//2):
        x,y=rng.randrange(16,w-8),rng.randrange(3,h-3)
        if abs(y-h//2)<3 or any(abs(x-b['x'])<6 and abs(y-b['y'])<7 for b in bases+factories):continue
        blocks.append([rng.choice([2,6,8,17,18]),x,y])
    robots=[{'owner':0,'x':13,'y':h//2+3,'parts':138},{'owner':0,'x':10,'y':h//2+5,'parts':17},
            {'owner':1,'x':w-17,'y':h//2,'parts':146}]
    data={'id':ident,'title':title,'subtitle':subtitle,'briefing':brief,'debrief':debrief,
          'width':w,'height':h,'seed':seed,'resources':32,'ai':ai,'capture_ticks':100,'day_ticks':180,
          'buildings':bases+factories,'elements':blocks,'obstacles':[],'starting_robots':robots,'next':nxt}
    dialogue = [
      ['Кестрел, вы на рубеже. Заводы нейтральны: у машин ещё нет хозяина.', 'Промышленная сеть отвечает. Вражеские базы начали развёртывание.', 'Два завода подключены. В архиве найдены координаты ретранслятора.'],
      ['Северный узел активен. Берегите антенны — это наши глаза под землёй.', 'Замечена переброска отрядов. Оставьте охрану у своей базы.', 'Это не команды. Ретранслятор передаёт чью-то память.'],
      ['Протокол выжигания запущен. Впереди три управляющих ядра.', 'Ядерные носители приближаются. Сохраняйте дистанцию между машинами.', 'Архив можно сохранить. Захватите ядра без ядерного подрыва.']][n]
    data['story']=[{'id':'arrival','tick':35,'text':dialogue[0]}, {'id':'response','tick':260,'text':dialogue[1]}, {'id':'discovery','factories':2,'text':dialogue[2]}]
    Path(f'data/maps/{ident}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
