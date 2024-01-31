function getFirstInitials() {
    let initials = ''

    if (typeof Person.Name.Initials !== 'undefined' && Person.Name.Initials) {
        initials = Person.Name.Initials;
    }

    if ((initials.length) > 10) {
        initials = initials.substring(0, 10)
    }

    return initials;
}

getFirstInitials();