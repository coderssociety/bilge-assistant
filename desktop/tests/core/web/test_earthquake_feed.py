import json
from datetime import UTC, datetime

import pytest

from bilge.core.web import earthquake_feed

AFAD = json.dumps([
    {"eventID": "597367", "location": "Sındırgı (Balıkesir)", "latitude": "39.23283", "longitude": "28.08317",
     "depth": "14.08", "type": "ML", "magnitude": "2.3", "country": "Türkiye", "province": "Balıkesir",
     "district": "Sındırgı", "date": "2026-10-25T15:40:56"},
    {"eventID": "597364", "location": "Ege Denizi - Kuşadası Körfezi - [10.82 km] Menderes (İzmir)",
     "latitude": "37.91883", "longitude": "27.11517", "depth": "7", "magnitude": "1", "country": "Türkiye",
     "province": None, "district": None, "date": "2026-10-25T14:39:54"},
    {"eventID": "596819", "location": "Bucharest (Romanya)", "latitude": "44.71633", "longitude": "26.024",
     "depth": "8.58", "magnitude": "4.3", "country": "Romanya", "province": "Kırklareli", "district": "Kofçaz",
     "date": "2026-10-25T16:52:04"},
    {"eventID": "broken", "latitude": "x", "longitude": "27", "depth": "7", "magnitude": "2", "date": "2026-10-25T10:00:00"},
    "not a row",
]).encode()  # fmt: skip

KANDILLI = """<HTML><title>Son Depremler</title><pre>
..................TÜRKİYE VE YAKIN ÇEVRESİNDEKİ SON DEPREMLER....................
                                                        Büyüklük
Tarih      Saat      Enlem(N)  Boylam(E) Derinlik(km)  MD   ML   Mw    Yer                                             Çözüm Niteliği
---------- --------  --------  -------   ----------    ------------    --------------                                  --------------
2026.10.25 19:46:48  37.7127   36.1195        9.6      -.-  1.6  -.-   ESENLI-SUMBAS (OSMANIYE)                          İlksel
2026.10.25 18:40:56  39.2415   28.0832       11.3      -.-  2.6  2.8   KOZLU-SINDIRGI (BALIKESIR)                        REVIZE01 (2026.10.25 18:45:10)
2026.10.25 17:56:12  37.9860   36.5917        7.4      -.-  1.6  -.-   KURUCAOVA-(KAHRAMANMARAS)                         İlksel
2026.10.25 17:18:58  34.5762   25.4058       11.2      -.-  2.5  -.-   GIRIT ADASI (AKDENIZ)                             İlksel
2026.10.25 16:00:00  37.2000   28.3600        5.0      -.-  2.0  -.-   MUGLA                                             İlksel
2026.10.25 15:00:00  37.2000   28.3600        5.0      -.-  -.-  -.-   NO MAGNITUDE (MUGLA)                              İlksel
</pre>""".encode("windows-1254")


def test_afad_rows_are_read_newest_first_and_broken_ones_skipped():
    quakes = earthquake_feed.parse_afad(AFAD)
    assert [q.id for q in quakes] == ["afad:596819", "afad:597367", "afad:597364"]
    sindirgi = quakes[1]
    assert sindirgi.time == datetime(2026, 10, 25, 15, 40, 56, tzinfo=UTC)
    assert (sindirgi.magnitude, sindirgi.depth_km, sindirgi.place) == (2.3, 14.08, "Sındırgı, Balıkesir")


def test_afad_places_abroad_and_offshore_read_well():
    places = [q.place for q in earthquake_feed.parse_afad(AFAD)]
    # Abroad AFAD fills in the nearest Turkish district, which would put Bucharest in Kırklareli.
    assert places[0] == "Bucharest (Romanya)"
    assert places[2] == "Ege Denizi - Kuşadası Körfezi - Menderes (İzmir)"


@pytest.mark.parametrize("body", [b"<html>maintenance</html>", b'{"error": "x"}'])
def test_an_afad_answer_that_is_not_a_list_is_an_error(body):
    with pytest.raises(ValueError):
        earthquake_feed.parse_afad(body)


def test_kandilli_rows_are_read_in_turkish_time():
    quakes = earthquake_feed.parse_kandilli(KANDILLI)
    assert len(quakes) == 5
    newest = quakes[0]
    assert newest.time == datetime(2026, 10, 25, 16, 46, 48, tzinfo=UTC)
    assert (newest.latitude, newest.longitude, newest.depth_km) == (37.7127, 36.1195, 9.6)
    assert newest.place == "Sumbas, Osmaniye"


def test_kandilli_prefers_mw_and_gives_provinces_their_spelling():
    by_place = {q.place: q for q in earthquake_feed.parse_kandilli(KANDILLI)}
    assert by_place["Sindirgi, Balıkesir"].magnitude == 2.8
    assert "Kurucaova, Kahramanmaraş" in by_place
    assert "Girit Adasi (Akdeniz)" in by_place
    assert "Muğla" in by_place


def test_the_same_earthquake_from_both_sources_is_recognised():
    afad = earthquake_feed.parse_afad(AFAD)[1]
    kandilli = next(q for q in earthquake_feed.parse_kandilli(KANDILLI) if "Balıkesir" in q.place)
    other = earthquake_feed.parse_kandilli(KANDILLI)[0]
    assert afad.same_as(kandilli) and kandilli.same_as(afad)
    assert not afad.same_as(other)
