function hash = sha256_file(filePath)
%SHA256_FILE Return lowercase SHA-256 for duplicate evidence detection.

arguments
    filePath (1,1) string
end

fid = fopen(filePath, "rb");
if fid < 0
    error("A2Analysis:HashOpen", "Cannot open for hashing: %s", filePath);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");
clear cleanup

digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
rawHash = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(rawHash, 2).', 1, [])));
end
