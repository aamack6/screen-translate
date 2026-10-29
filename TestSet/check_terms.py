"""Checks the listing-term matcher against the phrase fixtures without a Mac.

It runs a Python port of ListingTerms.matches that reads the term list straight from the Swift
source, so the word list can't drift. It is a check of the matching rules only; the Swift tests
(ScreenTranslateTests) run the real code. Usage: python3 TestSet/check_terms.py
"""
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import listing_terms_port as port

cases = json.load(open(os.path.join(here, '..', 'ScreenTranslateTests', 'Fixtures', 'listing_phrases.json')))
failures = 0
for case in cases:
    words = [m[0] for m in port.matches(case['text'])]
    missing = [w for w in case['expect'] if w not in words]
    wrong = [w for w in case['absent'] if w in words]
    if missing or wrong:
        failures += 1
        print(f"FAIL {case['id']}: {case['text']}\n  found {words}\n  missing {missing} unexpected {wrong}")
print(f"{len(cases) - failures}/{len(cases)} phrase cases pass")

# The shopping terms each synthetic screenshot should explain, from the text drawn on it.
shots = json.load(open(os.path.join(here, '..', 'ScreenTranslateTests', 'Fixtures', 'Screenshots', 'ground_truth.json'), encoding='utf-8'))
listings = {shot['listing']: shot for shot in shots}
shot_failures = 0
for listing in listings.values():
    words = [m[0] for line in listing['lines'] for m in port.matches(line)]
    missing = [w for w in listing['terms'] if not any(w in found for found in words)]
    if missing:
        shot_failures += 1
        print(f"FAIL screenshot {listing['listing']}: missing {missing}, found {words}")
print(f"{len(listings) - shot_failures}/{len(listings)} screenshot listings explain every expected term")
sys.exit(1 if failures or shot_failures else 0)
