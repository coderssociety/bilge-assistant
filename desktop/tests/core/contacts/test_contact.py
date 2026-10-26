from bilge.core.contacts.contact import Contact, find

PEOPLE = [
    Contact("Ahmet Yılmaz", ("0532 123 45 67",), ("ahmet@example.org",)),
    Contact("Ayşe Kaya", ("dahili 12", "+90 555 111 22 33"), ("ayse.kaya",), ("Ayşo",)),
    Contact("Mehmet Demir", nicknames=("Memo",)),
]


def test_a_first_name_with_a_turkish_ending_finds_the_person():
    assert find("Ahmet'in", PEOPLE) is PEOPLE[0]
    assert find("Ayşe'nin", PEOPLE) is PEOPLE[1]
    assert find("Memo", PEOPLE) is PEOPLE[2]
    assert find("Zeynep", PEOPLE) is None


def test_the_first_usable_number_and_address_are_picked():
    assert PEOPLE[0].phone == "+905321234567"
    assert PEOPLE[1].phone == "+905551112233"
    assert PEOPLE[1].email is None
    assert PEOPLE[2].phone is None
