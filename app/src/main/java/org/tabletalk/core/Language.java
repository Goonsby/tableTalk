package org.tabletalk.core;

public enum Language {
    ENGLISH("en"), SPANISH("es");
    public final String code;
    Language(String code) { this.code = code; }
    public Language other() { return this == ENGLISH ? SPANISH : ENGLISH; }
}
