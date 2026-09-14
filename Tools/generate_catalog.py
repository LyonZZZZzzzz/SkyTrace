#!/usr/bin/env python3
"""Build offline SkyTrace catalog resources from public-domain / BSD inputs."""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
from pathlib import Path

CONSTELLATION_NAMES = {
    "And": ("Andromeda", "仙女座"), "Ant": ("Antlia", "唧筒座"), "Aps": ("Apus", "天燕座"),
    "Aqr": ("Aquarius", "宝瓶座"), "Aql": ("Aquila", "天鹰座"), "Ara": ("Ara", "天坛座"),
    "Ari": ("Aries", "白羊座"), "Aur": ("Auriga", "御夫座"), "Boo": ("Boötes", "牧夫座"),
    "Cae": ("Caelum", "雕具座"), "Cam": ("Camelopardalis", "鹿豹座"), "Cnc": ("Cancer", "巨蟹座"),
    "CVn": ("Canes Venatici", "猎犬座"), "CMa": ("Canis Major", "大犬座"), "CMi": ("Canis Minor", "小犬座"),
    "Cap": ("Capricornus", "摩羯座"), "Car": ("Carina", "船底座"), "Cas": ("Cassiopeia", "仙后座"),
    "Cen": ("Centaurus", "半人马座"), "Cep": ("Cepheus", "仙王座"), "Cet": ("Cetus", "鲸鱼座"),
    "Cha": ("Chamaeleon", "堰蜓座"), "Cir": ("Circinus", "圆规座"), "Col": ("Columba", "天鸽座"),
    "Com": ("Coma Berenices", "后发座"), "CrA": ("Corona Australis", "南冕座"), "CrB": ("Corona Borealis", "北冕座"),
    "Crv": ("Corvus", "乌鸦座"), "Crt": ("Crater", "巨爵座"), "Cru": ("Crux", "南十字座"),
    "Cyg": ("Cygnus", "天鹅座"), "Del": ("Delphinus", "海豚座"), "Dor": ("Dorado", "剑鱼座"),
    "Dra": ("Draco", "天龙座"), "Equ": ("Equuleus", "小马座"), "Eri": ("Eridanus", "波江座"),
    "For": ("Fornax", "天炉座"), "Gem": ("Gemini", "双子座"), "Gru": ("Grus", "天鹤座"),
    "Her": ("Hercules", "武仙座"), "Hor": ("Horologium", "时钟座"), "Hya": ("Hydra", "长蛇座"),
    "Hyi": ("Hydrus", "水蛇座"), "Ind": ("Indus", "印第安座"), "Lac": ("Lacerta", "蝎虎座"),
    "Leo": ("Leo", "狮子座"), "LMi": ("Leo Minor", "小狮座"), "Lep": ("Lepus", "天兔座"),
    "Lib": ("Libra", "天秤座"), "Lup": ("Lupus", "豺狼座"), "Lyn": ("Lynx", "天猫座"),
    "Lyr": ("Lyra", "天琴座"), "Men": ("Mensa", "山案座"), "Mic": ("Microscopium", "显微镜座"),
    "Mon": ("Monoceros", "麒麟座"), "Mus": ("Musca", "苍蝇座"), "Nor": ("Norma", "矩尺座"),
    "Oct": ("Octans", "南极座"), "Oph": ("Ophiuchus", "蛇夫座"), "Ori": ("Orion", "猎户座"),
    "Pav": ("Pavo", "孔雀座"), "Peg": ("Pegasus", "飞马座"), "Per": ("Perseus", "英仙座"),
    "Phe": ("Phoenix", "凤凰座"), "Pic": ("Pictor", "绘架座"), "Psc": ("Pisces", "双鱼座"),
    "PsA": ("Piscis Austrinus", "南鱼座"), "Pup": ("Puppis", "船尾座"), "Pyx": ("Pyxis", "罗盘座"),
    "Ret": ("Reticulum", "网罟座"), "Sge": ("Sagitta", "天箭座"), "Sgr": ("Sagittarius", "人马座"),
    "Sco": ("Scorpius", "天蝎座"), "Scl": ("Sculptor", "玉夫座"), "Sct": ("Scutum", "盾牌座"),
    "Ser1": ("Serpens Caput", "巨蛇座（头）"), "Ser2": ("Serpens Cauda", "巨蛇座（尾）"),
    "Sex": ("Sextans", "六分仪座"), "Tau": ("Taurus", "金牛座"), "Tel": ("Telescopium", "望远镜座"),
    "Tri": ("Triangulum", "三角座"), "TrA": ("Triangulum Australe", "南三角座"), "Tuc": ("Tucana", "杜鹃座"),
    "UMa": ("Ursa Major", "大熊座"), "UMi": ("Ursa Minor", "小熊座"), "Vel": ("Vela", "船帆座"),
    "Vir": ("Virgo", "室女座"), "Vol": ("Volans", "飞鱼座"), "Vul": ("Vulpecula", "狐狸座"),
}

MESSIER_NAMES = {
    "M1": "蟹状星云", "M6": "蝴蝶星团", "M7": "托勒密星团", "M8": "礁湖星云",
    "M11": "野鸭星团", "M13": "武仙座大星团", "M16": "鹰状星云", "M17": "欧米伽星云",
    "M20": "三叶星云", "M27": "哑铃星云", "M31": "仙女座大星系", "M42": "猎户座大星云",
    "M44": "蜂巢星团", "M45": "昴星团", "M51": "涡状星系", "M57": "环状星云",
    "M63": "向日葵星系", "M64": "黑眼星系", "M81": "波德星系", "M82": "雪茄星系",
    "M87": "室女A星系", "M101": "风车星系", "M104": "草帽星系",
}

MESSIER_TYPES = {
    "gc": "球状星团", "oc": "疏散星团", "pn": "行星状星云", "sfr": "恒星形成区",
    "snr": "超新星遗迹", "gg": "星系", "g": "星系", "pos": "星群", "dn": "双星", "multi": "多星系统",
}

CITIES = [
    ("北京", 39.9042, 116.4074, "Asia/Shanghai"), ("上海", 31.2304, 121.4737, "Asia/Shanghai"),
    ("广州", 23.1291, 113.2644, "Asia/Shanghai"), ("深圳", 22.5431, 114.0579, "Asia/Shanghai"),
    ("成都", 30.5728, 104.0668, "Asia/Shanghai"), ("重庆", 29.5630, 106.5516, "Asia/Shanghai"),
    ("杭州", 30.2741, 120.1551, "Asia/Shanghai"), ("南京", 32.0603, 118.7969, "Asia/Shanghai"),
    ("武汉", 30.5928, 114.3055, "Asia/Shanghai"), ("西安", 34.3416, 108.9398, "Asia/Shanghai"),
    ("天津", 39.3434, 117.3616, "Asia/Shanghai"), ("苏州", 31.2989, 120.5853, "Asia/Shanghai"),
    ("青岛", 36.0671, 120.3826, "Asia/Shanghai"), ("厦门", 24.4798, 118.0894, "Asia/Shanghai"),
    ("昆明", 25.0389, 102.7183, "Asia/Shanghai"), ("乌鲁木齐", 43.8256, 87.6168, "Asia/Shanghai"),
    ("拉萨", 29.6520, 91.1721, "Asia/Shanghai"), ("哈尔滨", 45.8038, 126.5350, "Asia/Shanghai"),
    ("香港", 22.3193, 114.1694, "Asia/Hong_Kong"), ("澳门", 22.1987, 113.5439, "Asia/Macau"),
    ("台北", 25.0330, 121.5654, "Asia/Taipei"), ("东京", 35.6762, 139.6503, "Asia/Tokyo"),
    ("首尔", 37.5665, 126.9780, "Asia/Seoul"), ("新加坡", 1.3521, 103.8198, "Asia/Singapore"),
    ("曼谷", 13.7563, 100.5018, "Asia/Bangkok"), ("悉尼", -33.8688, 151.2093, "Australia/Sydney"),
    ("伦敦", 51.5074, -0.1278, "Europe/London"), ("巴黎", 48.8566, 2.3522, "Europe/Paris"),
    ("纽约", 40.7128, -74.0060, "America/New_York"), ("洛杉矶", 34.0522, -118.2437, "America/Los_Angeles"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bsc", type=Path, required=True)
    parser.add_argument("--constellations", type=Path, required=True)
    parser.add_argument("--messier", type=Path, required=True)
    parser.add_argument("--star-names-cn", type=Path, required=True)
    parser.add_argument("--star-names-en", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def parse_float(text: str) -> float | None:
    try:
        return float(text.strip())
    except (TypeError, ValueError):
        return None


def normalized_identifier(value: str) -> str:
    return value.replace("\u2009", "").replace("\xa0", "").strip().upper()


def load_star_names(path_cn: Path, path_en: Path) -> dict[int, dict[str, str]]:
    cn = json.loads(path_cn.read_text(encoding="utf-8"))
    en = json.loads(path_en.read_text(encoding="utf-8"))
    result: dict[int, dict[str, str]] = {}
    for key, value in en.items():
        try:
            hip = int(key)
        except ValueError:
            continue
        result[hip] = {
            "englishName": (value.get("name") or "").strip(),
            "designation": (value.get("desig") or "").strip(),
            "constellation": (value.get("c") or "").strip(),
            "hd": (value.get("hd") or "").strip(),
        }
    for key, value in cn.items():
        try:
            hip = int(key)
        except ValueError:
            continue
        result.setdefault(hip, {})["name"] = (value.get("name") or "").strip()
    return result


def build_stars(bsc_path: Path, name_lookup: dict[int, dict[str, str]], output: Path) -> tuple[int, list[dict]]:
    records: list[tuple[int, int, float, float, float, float]] = []
    labels: list[dict] = []
    hd_to_hip: dict[int, int] = {}
    for hip, value in name_lookup.items():
        hd = normalized_identifier(value.get("hd", ""))
        if hd.startswith("HD"):
            digits = re.sub(r"\D", "", hd)
            if digits:
                hd_to_hip[int(digits)] = hip

    for raw in bsc_path.read_text(encoding="ascii", errors="ignore").splitlines():
        line = raw.ljust(197)
        hr = int(line[0:4])
        bsc_name = line[4:14].strip()
        hd_text = line[25:31].strip()
        rah_text, ram_text = line[75:77].strip(), line[77:79].strip()
        ras = parse_float(line[79:83])
        sign = -1.0 if line[83:84] == "-" else 1.0
        decd_text, decm_text = line[84:86].strip(), line[86:88].strip()
        decs = parse_float(line[88:90])
        magnitude = parse_float(line[102:107])
        bv = parse_float(line[109:114])
        if not all((rah_text, ram_text, decd_text, decm_text)) or None in (ras, decs, magnitude):
            continue
        rah, ram = int(rah_text), int(ram_text)
        decd, decm = int(decd_text), int(decm_text)
        if magnitude > 6.5 or not math.isfinite(magnitude):
            continue
        ra = (rah + ram / 60.0 + ras / 3600.0) * 15.0
        dec = sign * (decd + decm / 60.0 + decs / 3600.0)
        hd = int(hd_text) if hd_text.isdigit() else 0
        hip = hd_to_hip.get(hd, 0)
        bv = 0.65 if bv is None or not math.isfinite(bv) else max(-0.4, min(2.0, bv))
        records.append((hr, hip, ra, dec, magnitude, bv))

        named = name_lookup.get(hip, {})
        name = named.get("name", "")
        english = named.get("englishName", "")
        designation = named.get("designation", "") or bsc_name
        if name or english or designation:
            labels.append({
                "hr": hr,
                "hip": hip,
                "name": name or english or f"HR {hr}",
                "englishName": english,
                "designation": designation,
                "magnitude": magnitude,
            })

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as handle:
        for record in records:
            handle.write(struct.pack("<I I f f f f", *record))
    return len(records), labels


def build_constellations(path: Path, output: Path) -> int:
    source = json.loads(path.read_text(encoding="utf-8"))
    items = {}
    for feature in source["features"]:
        code = feature["id"]
        geometry = feature["geometry"]
        coordinates = geometry["coordinates"]
        if geometry["type"] == "LineString":
            coordinates = [coordinates]
        normalized = []
        for line in coordinates:
            if len(line) < 2:
                continue
            normalized.append([[float(point[0]) % 360.0, float(point[1])] for point in line])
        if not normalized:
            continue
        english, chinese = CONSTELLATION_NAMES.get(code, (code, code))
        item = items.setdefault(code, {
            "id": code,
            "name": chinese,
            "englishName": english,
            "segments": [],
        })
        item["segments"].extend(normalized)
    output.write_text(json.dumps(list(items.values()), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return len(items)


def build_deep_sky(path: Path, output: Path) -> int:
    source = json.loads(path.read_text(encoding="utf-8"))
    items = []
    for feature in source["features"]:
        properties = feature["properties"]
        identifier = feature["id"]
        object_type = MESSIER_TYPES.get(properties.get("type", ""), "深空天体")
        english = properties.get("alt") or object_type
        items.append({
            "id": identifier,
            "name": MESSIER_NAMES.get(identifier, f"{identifier}（{object_type}）"),
            "englishName": english,
            "designation": properties.get("desig", ""),
            "type": object_type,
            "category": properties.get("type", ""),
            "magnitude": properties.get("mag"),
            "ra": float(feature["geometry"]["coordinates"][0]) % 360.0,
            "dec": float(feature["geometry"]["coordinates"][1]),
        })
    output.write_text(json.dumps(items, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return len(items)


def build_cities(output: Path) -> None:
    payload = [
        {"name": name, "latitude": latitude, "longitude": longitude, "timeZone": timezone}
        for name, latitude, longitude, timezone in CITIES
    ]
    output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    name_lookup = load_star_names(args.star_names_cn, args.star_names_en)
    star_count, star_labels = build_stars(args.bsc, name_lookup, args.output / "Stars.bin")
    constellation_count = build_constellations(args.constellations, args.output / "Constellations.json")
    deep_sky_count = build_deep_sky(args.messier, args.output / "DeepSky.json")
    (args.output / "StarLabels.json").write_text(
        json.dumps(star_labels, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    build_cities(args.output / "Cities.json")
    print(json.dumps({
        "stars": star_count,
        "constellations": constellation_count,
        "deepSky": deep_sky_count,
        "starLabels": len(star_labels),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
