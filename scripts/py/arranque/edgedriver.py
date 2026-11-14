# -*- coding: utf-8 -*-
r"""Deja en EDGEDRIVER_PATH el msedgedriver.exe de la misma version que el Edge
instalado (equivale a scripts\arranque\ACTUALIZAR_EDGEDRIVER.ps1, sin PowerShell).

Edge se actualiza solo y el driver debe coincidir con su version; si no coincide se
descarga de la web oficial de Microsoft y solo se usa si esta firmado por Microsoft
(verificacion fail-closed: ante cualquier duda, se rechaza). Codigo 0 si queda listo.
"""
import ctypes
import os
import shutil
import struct
import sys
import tempfile
import urllib.request
import zipfile
from ctypes import wintypes
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config

EDGE_EXES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


def _product_version(path):
    """Lee ProductVersion de los metadatos del fichero (sin ejecutarlo). '' si no hay."""
    path = str(path)
    if not os.path.exists(path):
        return ""
    ver = ctypes.windll.version
    size = ver.GetFileVersionInfoSizeW(path, None)
    if not size:
        return ""
    buf = ctypes.create_string_buffer(size)
    if not ver.GetFileVersionInfoW(path, 0, size, buf):
        return ""
    lplp = ctypes.c_void_p()
    length = wintypes.UINT()
    # Idioma/codepage del bloque de strings.
    if not ver.VerQueryValueW(buf, r"\VarFileInfo\Translation",
                              ctypes.byref(lplp), ctypes.byref(length)) or not length.value:
        return ""
    lang, codepage = struct.unpack("<HH", ctypes.string_at(lplp.value, 4))
    sub = f"\\StringFileInfo\\{lang:04x}{codepage:04x}\\ProductVersion"
    if not ver.VerQueryValueW(buf, sub, ctypes.byref(lplp), ctypes.byref(length)) or not length.value:
        return ""
    return ctypes.wstring_at(lplp.value, length.value - 1)


def _firmado_por_microsoft(path):
    """True solo si el fichero tiene firma Authenticode valida y confiable Y el firmante
    es 'Microsoft Corporation'. Fail-closed: cualquier error devuelve False."""
    try:
        if _winverifytrust(path) != 0:
            return False
        return "Microsoft Corporation" in _signer_org(path)
    except Exception:
        return False


def _winverifytrust(path):
    # WINTRUST_ACTION_GENERIC_VERIFY_V2
    class GUID(ctypes.Structure):
        _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD), ("c", wintypes.WORD),
                    ("d", ctypes.c_ubyte * 8)]

    guid = GUID(0xAAC56B, 0xCD44, 0x11D0, (0x8C, 0xC2, 0x00, 0xC0, 0x4F, 0xC2, 0x95, 0xEE))

    class FILE_INFO(ctypes.Structure):
        _fields_ = [("cbStruct", wintypes.DWORD), ("pcwszFilePath", wintypes.LPCWSTR),
                    ("hFile", wintypes.HANDLE), ("pgKnownSubject", ctypes.c_void_p)]

    class WINTRUST_DATA(ctypes.Structure):
        _fields_ = [("cbStruct", wintypes.DWORD), ("pPolicyCallbackData", ctypes.c_void_p),
                    ("pSIPClientData", ctypes.c_void_p), ("dwUIChoice", wintypes.DWORD),
                    ("fdwRevocationChecks", wintypes.DWORD), ("dwUnionChoice", wintypes.DWORD),
                    ("pFile", ctypes.POINTER(FILE_INFO)), ("dwStateAction", wintypes.DWORD),
                    ("hWVTStateData", wintypes.HANDLE), ("pwszURLReference", wintypes.LPCWSTR),
                    ("dwProvFlags", wintypes.DWORD), ("dwUIContext", wintypes.DWORD),
                    ("pSignatureSettings", ctypes.c_void_p)]

    fi = FILE_INFO(ctypes.sizeof(FILE_INFO), str(path), None, None)
    data = WINTRUST_DATA()
    data.cbStruct = ctypes.sizeof(WINTRUST_DATA)
    data.dwUIChoice = 2          # WTD_UI_NONE
    data.fdwRevocationChecks = 0  # WTD_REVOKE_NONE
    data.dwUnionChoice = 1        # WTD_CHOICE_FILE
    data.pFile = ctypes.pointer(fi)
    data.dwStateAction = 1        # WTD_STATEACTION_VERIFY
    data.dwProvFlags = 0x00000010  # WTD_SAFER_FLAG
    rc = ctypes.windll.wintrust.WinVerifyTrust(None, ctypes.byref(guid), ctypes.byref(data))
    data.dwStateAction = 2        # WTD_STATEACTION_CLOSE
    ctypes.windll.wintrust.WinVerifyTrust(None, ctypes.byref(guid), ctypes.byref(data))
    return rc


_prototipos_listos = False


def _preparar_crypt32():
    """Declara restype/argtypes de crypt32: sin esto, en Python 64 bits los punteros
    devueltos se truncan a 32 bits y provocan access violations."""
    global _prototipos_listos
    if _prototipos_listos:
        return
    crypt = ctypes.windll.crypt32
    LPVOID = ctypes.c_void_p
    crypt.CryptQueryObject.restype = wintypes.BOOL
    crypt.CryptMsgGetParam.restype = wintypes.BOOL
    crypt.CertFindCertificateInStore.restype = LPVOID
    crypt.CertFindCertificateInStore.argtypes = [
        wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, LPVOID, LPVOID]
    crypt.CertGetNameStringW.restype = wintypes.DWORD
    crypt.CertGetNameStringW.argtypes = [
        LPVOID, wintypes.DWORD, wintypes.DWORD, LPVOID, wintypes.LPWSTR, wintypes.DWORD]
    crypt.CertFreeCertificateContext.argtypes = [LPVOID]
    crypt.CertCloseStore.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    crypt.CryptMsgClose.argtypes = [wintypes.HANDLE]
    _prototipos_listos = True


def _signer_org(path):
    """Organizacion del certificado firmante (via CryptQueryObject). '' si no se puede."""
    _preparar_crypt32()
    crypt = ctypes.windll.crypt32
    CERT_QUERY_OBJECT_FILE = 1
    CERT_QUERY_CONTENT_FLAG_ALL = 0x3FFE
    CERT_QUERY_FORMAT_FLAG_ALL = 0x0E
    CMSG_SIGNER_CERT_INFO_PARAM = 7
    CERT_FIND_SUBJECT_CERT = 0x000B0007
    CERT_NAME_ATTR_TYPE = 3
    X509_ASN_ENCODING = 0x1
    PKCS_7_ASN_ENCODING = 0x10010000

    h_store = wintypes.HANDLE()
    h_msg = wintypes.HANDLE()
    if not crypt.CryptQueryObject(
            CERT_QUERY_OBJECT_FILE, ctypes.c_wchar_p(str(path)),
            CERT_QUERY_CONTENT_FLAG_ALL, CERT_QUERY_FORMAT_FLAG_ALL, 0,
            None, None, None, ctypes.byref(h_store), ctypes.byref(h_msg), None):
        return ""
    try:
        size = wintypes.DWORD()
        crypt_msg = ctypes.windll.crypt32.CryptMsgGetParam
        if not crypt_msg(h_msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, None, ctypes.byref(size)) or not size.value:
            return ""
        info = ctypes.create_string_buffer(size.value)
        if not crypt_msg(h_msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, info, ctypes.byref(size)):
            return ""
        cert = crypt.CertFindCertificateInStore(
            h_store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
            CERT_FIND_SUBJECT_CERT, info, None)
        if not cert:
            return ""
        try:
            szOID_ORG = b"2.5.4.10"
            n = crypt.CertGetNameStringW(cert, CERT_NAME_ATTR_TYPE, 0, ctypes.c_char_p(szOID_ORG), None, 0)
            if n <= 1:
                return ""
            out = ctypes.create_unicode_buffer(n)
            crypt.CertGetNameStringW(cert, CERT_NAME_ATTR_TYPE, 0, ctypes.c_char_p(szOID_ORG), out, n)
            return out.value
        finally:
            crypt.CertFreeCertificateContext(cert)
    finally:
        if h_msg:
            crypt.CryptMsgClose(h_msg)
        if h_store:
            crypt.CertCloseStore(h_store, 0)


def main():
    cfg = _config.cargar()
    driver = cfg.get("EDGEDRIVER_PATH", "")
    edge_exe = next((e for e in EDGE_EXES if os.path.exists(e)), None)
    if not edge_exe:
        print("ERROR: Microsoft Edge no esta instalado.")
        return 1
    edge_version = _product_version(edge_exe)
    actual = _product_version(driver)
    if actual == edge_version:
        print(f"msedgedriver {actual} ya coincide con Edge {edge_version}")
        return 0

    print(f"Edge {edge_version} y msedgedriver '{actual}' no coinciden: descargando el driver oficial...")
    work = Path(tempfile.gettempdir()) / f"msedgedriver-{edge_version}-{os.getpid()}"
    work.mkdir(parents=True, exist_ok=True)
    try:
        zip_path = work / "edgedriver_win64.zip"
        urllib.request.urlretrieve(
            f"https://msedgedriver.microsoft.com/{edge_version}/edgedriver_win64.zip", zip_path)
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(work)
        descargado = work / "msedgedriver.exe"
        if not _firmado_por_microsoft(descargado):
            raise RuntimeError("el driver descargado no esta firmado por Microsoft")
        Path(driver).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(descargado, driver)
        print(f"msedgedriver actualizado a {_product_version(driver)} en {driver}")
        return 0
    except Exception as e:
        print(f"ERROR: no se pudo actualizar msedgedriver: {e}")
        return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
