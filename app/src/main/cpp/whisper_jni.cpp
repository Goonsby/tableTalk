#include <jni.h>
#include <whisper.h>
#include <atomic>
#include <memory>
#include <string>
#include <cstring>

namespace {
struct Session {
    whisper_context *ctx = nullptr;
    std::atomic_bool cancelled{false};
    ~Session() { if (ctx) whisper_free(ctx); }
};
void quiet_log(ggml_log_level, const char *, void *) { }
bool aborted(void *data) { return static_cast<Session *>(data)->cancelled.load(); }
void fail(JNIEnv *env, const char *type, const char *message) {
    jclass cls = env->FindClass(type);
    if (cls) { env->ThrowNew(cls, message); env->DeleteLocalRef(cls); }
}
Session *session(jlong handle) { return reinterpret_cast<Session *>(handle); }
}

extern "C" JNIEXPORT jlong JNICALL
Java_org_tabletalk_inference_WhisperEngine_nativeCreate(JNIEnv *env, jclass, jstring path) {
    whisper_log_set(quiet_log, nullptr);
    ggml_log_set(quiet_log, nullptr);
    const char *file = env->GetStringUTFChars(path, nullptr);
    if (!file) return 0;
    auto result = std::make_unique<Session>();
    auto params = whisper_context_default_params();
    params.use_gpu = false;
    result->ctx = whisper_init_from_file_with_params(file, params);
    env->ReleaseStringUTFChars(path, file);
    if (!result->ctx || !whisper_is_multilingual(result->ctx)
            || whisper_model_n_audio_layer(result->ctx) > 6) {
        fail(env, "java/lang/IllegalArgumentException", "Choose the multilingual tiny or base speech model");
        return 0;
    }
    return reinterpret_cast<jlong>(result.release());
}

extern "C" JNIEXPORT void JNICALL
Java_org_tabletalk_inference_WhisperEngine_nativeRelease(JNIEnv *, jclass, jlong handle) {
    delete session(handle);
}
extern "C" JNIEXPORT void JNICALL
Java_org_tabletalk_inference_WhisperEngine_nativeCancel(JNIEnv *, jclass, jlong handle) {
    session(handle)->cancelled.store(true);
}
extern "C" JNIEXPORT void JNICALL
Java_org_tabletalk_inference_WhisperEngine_nativeResetCancellation(JNIEnv *, jclass, jlong handle) {
    session(handle)->cancelled.store(false);
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_tabletalk_inference_WhisperEngine_nativeTranscribe(
        JNIEnv *env, jclass, jlong handle, jfloatArray audio, jstring language, jint threads) {
    auto *s = session(handle);
    int count = env->GetArrayLength(audio);
    if (count < 8000 || count > 16000 * 12) {
        fail(env, "java/lang/IllegalArgumentException", "Audio must be 0.5 to 12 seconds");
        return nullptr;
    }
    const char *lang = env->GetStringUTFChars(language, nullptr);
    if (!lang) return nullptr;
    if (std::strcmp(lang, "en") != 0 && std::strcmp(lang, "es") != 0) {
        env->ReleaseStringUTFChars(language, lang);
        fail(env, "java/lang/IllegalArgumentException", "Unsupported language");
        return nullptr;
    }
    jfloat *pcm = env->GetFloatArrayElements(audio, nullptr);
    if (!pcm) { env->ReleaseStringUTFChars(language, lang); return nullptr; }
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = threads;
    params.language = lang;
    params.translate = false;
    params.no_context = true;
    params.no_timestamps = true;
    params.single_segment = true;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.temperature = 0.0f;
    params.temperature_inc = 0.0f;
    params.abort_callback = aborted;
    params.abort_callback_user_data = s;
    int code = s->cancelled.load() ? -1 : whisper_full(s->ctx, params, pcm, count);
    // Clear any JNI copy before release, then Java clears its own array too.
    volatile float *wipe = pcm;
    for (int i = 0; i < count; ++i) wipe[i] = 0;
    env->ReleaseFloatArrayElements(audio, pcm, JNI_ABORT);
    env->ReleaseStringUTFChars(language, lang);
    if (s->cancelled.load()) {
        fail(env, "java/util/concurrent/CancellationException", "Speech processing cancelled");
        return nullptr;
    }
    if (code != 0) {
        fail(env, "java/lang/IllegalStateException", "Speech processing failed");
        return nullptr;
    }
    std::string text;
    for (int i = 0; i < whisper_full_n_segments(s->ctx); ++i) {
        // Non-speech probability is a heuristic, not calibrated accuracy.
        if (whisper_full_get_segment_no_speech_prob(s->ctx, i) > 0.8f) continue;
        text += whisper_full_get_segment_text(s->ctx, i);
    }
    auto result = env->NewByteArray(static_cast<jsize>(text.size()));
    if (result) env->SetByteArrayRegion(result, 0, static_cast<jsize>(text.size()),
                                      reinterpret_cast<const jbyte *>(text.data()));
    return result;
}
