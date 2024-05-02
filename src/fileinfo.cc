#include <cassert>
#include <cstdint>
#include <filesystem>
#include <iostream>

namespace fs = std::filesystem;

extern "C" bool isDirRaw(const char* path, bool* result) {
    assert(path != nullptr && result != nullptr);
    std::error_code errcode;

    *result = fs::is_directory(path, errcode);

    if (errcode) {
        std::cerr << "ERROR (fileinfo.cc): " << errcode.message() << '\n';
        return false;
    }

    return true;
}

extern "C" bool fileSizeRaw(const char* path, uintmax_t* result) {
    assert(path != nullptr && result != nullptr);
    std::error_code errcode;

    *result = fs::file_size(path, errcode);

    if (errcode) {
        std::cerr << "ERROR (fileinfo.cc): " << errcode.message() << '\n';
        return false;
    }

    return true;
}
