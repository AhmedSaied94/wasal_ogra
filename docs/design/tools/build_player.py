"""Build the Lottie preview page (all generated animations, playable by segment).
usage: python3 build_player.py <lottie dir> <out html> <lottie script src>
"""
import json, os, sys
LDIR, OUT, LIBSRC = sys.argv[1], sys.argv[2], sys.argv[3]
AR = {
 "regular":"العادي","hagga":"الحاجة","sleeper":"النايم","hurried":"المستعجل","effendi_200":"الأفندي أبو ٢٠٠","student":"الطالب",
 "headphones":"أبو سمّاعة","claimer":"«أنا دافع!»","group_payer":"«خلّيها عليّا»","chatterbox":"الرغّاي","changer":"اللي بيفك",
 "bags_lady":"الست بالشنط","dodger":"المتهرب","mother_kids":"الأم والعيال","big_family":"العيلة الكبيرة","traveler":"المسافر",
 "regular_customer":"الزبون الدايم","honest":"الأمين",
 "usta":"الأسطى","salma":"سلمى","bride_father":"أبو العروسة","bride_mother":"أم العروسة","moallem":"المعلم","belya":"بلية",
 "tuktuk":"توكتوك المعلم","microbus_old":"ميكروباص قديم","microbus_new":"ميكروباص جديد","microbus_travel":"ميكروباص سفر",
 "splash_drive":"شاشة التحميل","coach_hand":"إيد التعليم","stars":"النجوم","coins_burst":"جنيهات طايرة","bonat_burst":"بونات طايرة",
 "confetti":"احتفال","fuel_fill":"عدّاد البنزين","gift_open":"الهدية","sparkle_place":"تركيب قطعة","ring_shine":"لمعة الشبكة",
 "loading_wheel":"تحميل","notif_bell":"جرس الإشعارات"}
ORDER = {"passengers":["regular","hagga","sleeper","hurried","effendi_200","student","headphones","claimer","group_payer","chatterbox","changer","bags_lady","dodger","mother_kids","big_family","traveler","regular_customer","honest"],
         "characters":["usta","salma","bride_father","bride_mother","moallem","belya"],
         "vehicles":["tuktuk","microbus_old","microbus_new","microbus_travel"],
         "ui":["splash_drive","coach_hand","stars","coins_burst","bonat_burst","confetti","fuel_fill","gift_open","sparkle_place","ring_shine","loading_wheel","notif_bell"]}
LOOPS = {"idle","talk","impatient_1","impatient_2","sleep","headphones","change_due","fight","claim","surprised","angry","drive","loop","tap","ring"}
data = {}
for grp, ids in ORDER.items():
    for i in ids:
        data[f"{grp}/{i}"] = json.load(open(os.path.join(LDIR, grp, i + ".json")))
meta = [{"key": k, "group": k.split("/")[0], "id": k.split("/")[1], "ar": AR[k.split("/")[1]],
         "markers": [m["cm"] for m in v["markers"]]} for k, v in data.items()]
html = open(os.path.join(os.path.dirname(__file__), "player_template.html")).read()
html = html.replace("%%LIB%%", LIBSRC).replace("%%META%%", json.dumps(meta, ensure_ascii=False)) \
           .replace("%%LOOPS%%", json.dumps(sorted(LOOPS))).replace("%%DATA%%", json.dumps(data, separators=(",", ":")))
open(OUT, "w").write(html)
print(OUT, round(len(html) / 1e6, 2), "MB")
