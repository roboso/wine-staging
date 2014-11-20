import email.header
    def __init__(self, filename, header):
        self.patch_author       = header['author']
        self.patch_email        = header['email']
        self.patch_subject      = header['subject']
        self.patch_revision     = header['revision'] if header.has_key('revision') else 1
        self.extracted_patch    = None
        self.unique_hash        = None
        self.filename           = filename
        self.offset_begin       = None
        self.offset_end         = None
        self.isbinary           = False
        self.oldname            = None
        self.newname            = None
        self.modified_file      = None

        self.oldsha1            = None
        self.newsha1            = None
        self.newmode            = None
    def _read_single_patch(fp, header, oldname=None, newname=None):
        patch = PatchObject(fp.filename, header)











                try:
                    while srclines > 0 or dstlines > 0:
                        line = fp.read()[0]
                        if line == " ":
                            if srclines == 0 or dstlines == 0:
                                raise PatchParserError("Corrupted patch.")
                            srclines -= 1
                            dstlines -= 1
                        elif line == "-":
                            if srclines == 0:
                                raise PatchParserError("Corrupted patch.")
                            srclines -= 1
                        elif line == "+":
                            if dstlines == 0:
                                raise PatchParserError("Corrupted patch.")
                            dstlines -= 1
                        elif line == "\\":
                            pass # ignore
                        else:
                            raise PatchParserError("Unexpected line in hunk.")
                except TypeError: # triggered by None[0]
                    raise PatchParserError("Truncated patch.")
    def _parse_author(author):
        author = ' '.join([data.decode(format or 'utf-8').encode('utf-8') for \
                          data, format in email.header.decode_header(author)])
        r =  re.match("\"?([^\"]*)\"? <(.*)>", author)
        if r is None: raise NotImplementedError("Failed to parse From - header.")
        return r.group(1).strip(), r.group(2).strip()

    def _parse_subject(subject):
        version = "(v|try|rev|take) *([0-9]+)"
        subject = subject.strip()
        if subject.endswith("."): subject = subject[:-1]
        r = re.match("^\\[PATCH([^]]*)\\](.*)$", subject, re.IGNORECASE)
        if r is not None:
            subject = r.group(2).strip()
            r = re.search(version, r.group(1), re.IGNORECASE)
            if r is not None: return subject, int(r.group(2))
        r = re.match("^(.*)\\(%s\\)$" % version, subject, re.IGNORECASE)
        if r is not None: return r.group(1).strip(), int(r.group(3))
        r = re.match("^(.*)[.,] +%s$" % version, subject, re.IGNORECASE)
        if r is not None: return r.group(1).strip(), int(r.group(3))
        r = re.match("^([^:]+) %s: (.*)$" % version, subject, re.IGNORECASE)
        if r is not None: return "%s: %s" % (r.group(1), r.group(4)), int(r.group(3))
        r = re.match("^(.*) +%s$" % version, subject, re.IGNORECASE)
        if r is not None: return r.group(1).strip(), int(r.group(3))
        return subject, 1

    header = {}

            elif line.startswith("From: "):
                header['author'], header['email'] = _parse_author(line[6:])
                assert fp.read() == line

            elif line.startswith("Subject: "):
                subject = line[9:].rstrip("\r\n")
                assert fp.read() == line
                while True:
                    line = fp.peek()
                    if not line.startswith(" "): break
                    subject += line.rstrip("\r\n")
                    assert fp.read() == line
                subject, revision = _parse_subject(subject)
                if not subject.endswith("."): subject += "."
                header['subject'], header['revision'] = subject, revision

                yield _read_single_patch(fp, header, tmp[2].strip(), tmp[3].strip())

                yield _read_single_patch(fp, header)


            cmdline = ["patch", "--no-backup-if-mismatch", "--force", "--silent", "-r", "-"]