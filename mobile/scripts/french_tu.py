#!/usr/bin/env python3
"""Oort NX says "tu" in French. Rewrites the polite forms of the catalogues brought from NX2Apple, or lists them with --check."""
import json
from pathlib import Path
import re
import sys

CATALOGUES = [Path(__file__).resolve().parents[1] / "Sources" / name / "Resources/Localizable.xcstrings" for name in ("OortMobile", "ShellHost", "ShellModel")]
CATALOGUES.append(Path(__file__).resolve().parents[1] / "App/InfoPlist.xcstrings")
PHRASES = [
    ("voulez-vous utiliser", "veux-tu utiliser"), ("voulez-vous", "veux-tu"), ("vous n’en choisirez pas", "tu n’en choisiras pas"),
    ("vous n’aurez pas importé", "tu n’auras pas importé"), ("vous avez choisi vous-même", "tu as choisi toi-même"),
    ("vous ne choisissez pas", "tu ne choisis pas"), ("vous choisissez", "tu choisis"), ("Vous choisissez", "Tu choisis"), ("Vous pouvez", "Tu peux"),
    ("Vous reviendrez", "Tu reviendras"), ("vous appuyez", "tu appuies"), ("Vous en copiez", "Tu en copies"), ("Essayez-en", "Essaie-en"),
    ("Touchez-en", "Touches-en"), ("Associez-en", "Associes-en"),
]
WORDS = """Recompilez Recompile,Réinstallez Réinstalle,Choisissez Choisis,Téléchargez Télécharge,Réessayez Réessaie,Reconnectez Reconnecte,Touchez Touche,
Renommez Renomme,Glissez Glisse,Attendez Attends,Renvoyez Renvoie,Recopiez Recopie,Envoyez Envoie,Copiez Copie,Essayez Essaie,Ouvrez Ouvre,Mettez Mets,
Fermez Ferme,Rouvrez Rouvre,Importez Importe,Utilisez Utilise,Ajoutez Ajoute,Autorisez Autorise,Accédez Accède,Connectez Connecte,Laissez Laisse,
Faites Fais,Déplacez Déplace,Pincez Pince,Modifiez Modifie,Enregistrez Enregistre,Saisissez Saisis,Placez Place,Recherchez Recherche,Installez Installe,
Désactivez Désactive,Appuyez Appuie,Renouvelez Renouvelle,Consultez Consulte,Partagez Partage,Lancez Lance,Changez Change,Collez Colle,
Sélectionnez Sélectionne,Transférez Transfère,Compilez Compile,Gardez Garde,Activez Active"""
FEMININE = "sauvegarde|manette|bibliothèque"
POLITE = re.compile(r"\b(?:vous|votre|vos|\w+ez|faites)\b(?<!chez)(?<!assez)(?<!nez)", re.IGNORECASE)
KEEP = {"chez", "assez"}


def tu(text):
    for old, new in PHRASES:
        text = text.replace(old, new)
    for pair in WORDS.replace("\n", "").split(","):
        old, new = pair.split()
        for a, b in ((old, new), (old.lower(), new.lower())):
            text = re.sub(rf"\b{a}\b", b, text)
    for a, b in (("votre", "ton"), ("Votre", "Ton")):
        text = re.sub(rf"\b{a} ({FEMININE})\b", lambda m: ("T" if a[0] == "V" else "t") + "a " + m.group(1), text)
        text = re.sub(rf"\b{a}\b", b, text)
    return re.sub(r"\bVos\b", "Tes", re.sub(r"\bvos\b", "tes", text))


def units(node):
    if isinstance(node, dict):
        if isinstance(node.get("stringUnit"), dict):
            yield node["stringUnit"]
        for key, value in node.items():
            if key != "stringUnit":
                yield from units(value)


def main(check):
    left = []
    for path in CATALOGUES:
        raw = path.read_text()
        for entry in json.loads(raw)["strings"].values():
            for unit in units(entry.get("localizations", {}).get("fr", {})):
                new = tu(unit["value"])
                if new != unit["value"]:
                    if check:
                        left.append(unit["value"])
                    else:
                        for old, text in ((json.dumps(unit["value"], ensure_ascii=False), json.dumps(new, ensure_ascii=False)),):
                            raw = raw.replace(old, text)
                elif any(m not in KEEP for m in (x.lower() for x in POLITE.findall(new))):
                    left.append(new)
        if not check:
            path.write_text(raw)
    print("\n".join(left) or "tu everywhere")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
