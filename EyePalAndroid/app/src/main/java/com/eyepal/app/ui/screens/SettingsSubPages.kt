package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import java.util.Locale
import com.eyepal.app.config.Defaults
import androidx.compose.ui.res.stringResource
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.services.FaceRecognitionLogStore
import com.eyepal.app.services.OAuthService
import com.eyepal.app.services.OcrEngine
import com.eyepal.app.services.OcrEngineLog
import com.eyepal.app.services.TranslationService
import com.eyepal.app.services.GemmaModelKind
import com.eyepal.app.services.GemmaDownloadState
import com.eyepal.app.services.GemmaModelManager
import com.eyepal.app.viewmodels.QuickCaptionLength
import com.eyepal.app.viewmodels.QuickContinuousInterval
import com.eyepal.app.viewmodels.QuickTriggerMode
import com.eyepal.app.viewmodels.RecognitionActionControlStyle
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailsRecognitionSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val scope = rememberCoroutineScope()
    var isSignedIn by remember { mutableStateOf(OAuthService.isSignedIn(context)) }

    val savedButtonsJson by settings.detailButtons.collectAsState(initial = "")
    val controlStyle by settings.detailsActionControlStyle.collectAsState(initial = com.eyepal.app.config.Defaults.DETAILS_ACTION_CONTROL_STYLE)
    val buttonTypes = listOf("Product", "Dish", "Short Text", "Custom")
    var buttons by remember(savedButtonsJson) {
        mutableStateOf(
            try {
                if (savedButtonsJson.isNotEmpty()) {
                    val arr = org.json.JSONArray(savedButtonsJson)
                    (0 until arr.length()).map { i ->
                        val obj = arr.getJSONObject(i)
                        Triple(obj.optString("name", ""), obj.optString("prompt", ""), obj.optString("type", "Custom"))
                    }.take(4)
                } else {
                    listOf(Triple("Custom", "For a blind user, first read visible text exactly. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks.", "Custom"),
                           Triple("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name, packaging details, and primary function.", "Product"),
                           Triple("Dish", "Describe the dish layout in detail for a blind user, including portions, relative positions, and likely ingredients.", "Dish"),
                           Triple("Short Text", "Read the visible short text and numbers exactly, and mention where they appear in the scene.", "Short Text"))
                }
            } catch (_: Exception) {
                listOf(Triple("Custom", "For a blind user, first read visible text exactly. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks.", "Custom"),
                       Triple("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name, packaging details, and primary function.", "Product"),
                       Triple("Dish", "Describe the dish layout in detail for a blind user, including portions, relative positions, and likely ingredients.", "Dish"),
                       Triple("Short Text", "Read the visible short text and numbers exactly, and mention where they appear in the scene.", "Short Text"))
            }
        )
    }

    fun saveButtons() {
        val arr = org.json.JSONArray()
        buttons.forEach { (name, prompt, type) ->
            arr.put(org.json.JSONObject().apply {
                put("name", name)
                put("prompt", prompt)
                put("type", type)
            })
        }
        scope.launch { settings.setDetailButtons(arr.toString()) }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.feature_details_recognition)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
        Spacer(modifier = Modifier.height(16.dp))

        Text(stringResource(R.string.settings_chatgpt_account), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(8.dp))

        if (isSignedIn) {
            Text(stringResource(R.string.label_signed_in), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = {
                OAuthService.signOut(context)
                isSignedIn = false
            }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) {
                Text(stringResource(R.string.btn_sign_out))
            }
        } else {
            Text(stringResource(R.string.label_not_signed_in), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.outline)
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text(stringResource(R.string.settings_scene_description), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(4.dp))

        Spacer(modifier = Modifier.height(20.dp))
        Text(stringResource(R.string.settings_control_style), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(8.dp))
        val currentControlStyle = RecognitionActionControlStyle.fromValue(controlStyle)
        var expandedControlStyle by remember { mutableStateOf(false) }
        ExposedDropdownMenuBox(expanded = expandedControlStyle, onExpandedChange = { expandedControlStyle = it }) {
            OutlinedTextField(
                value = stringResource(currentControlStyle.labelRes),
                onValueChange = {},
                readOnly = true,
                label = { Text(stringResource(R.string.settings_control_style)) },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedControlStyle) },
                modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
            )
            ExposedDropdownMenu(expanded = expandedControlStyle, onDismissRequest = { expandedControlStyle = false }) {
                RecognitionActionControlStyle.entries.forEach { entry ->
                    DropdownMenuItem(text = { Text(stringResource(entry.labelRes)) }, onClick = {
                        scope.launch { settings.setDetailsActionControlStyle(entry.value) }
                        expandedControlStyle = false
                    })
                }
            }
        }
        Spacer(modifier = Modifier.height(20.dp))
        Text(stringResource(R.string.settings_detail_buttons), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(8.dp))

        buttons.forEachIndexed { index, (name, prompt, type) ->
            Text(stringResource(R.string.label_button, index + 1), style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(4.dp))
            OutlinedTextField(
                value = name,
                onValueChange = { newName ->
                    buttons = buttons.toMutableList().apply { set(index, Triple(newName, prompt, type)) }
                    saveButtons()
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.label_name)) },
                singleLine = true
            )
            Spacer(modifier = Modifier.height(4.dp))
            OutlinedTextField(
                value = prompt,
                onValueChange = { newPrompt ->
                    buttons = buttons.toMutableList().apply { set(index, Triple(name, newPrompt, type)) }
                    saveButtons()
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.label_prompt)) },
                maxLines = 3
            )
            Spacer(modifier = Modifier.height(4.dp))
            var expandedType by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { expandedType = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.label_type, type))
                }
                DropdownMenu(expanded = expandedType, onDismissRequest = { expandedType = false }) {
                    buttonTypes.forEach { t ->
                        DropdownMenuItem(
                            text = { Text(t) },
                            onClick = {
                                buttons = buttons.toMutableList().apply { set(index, Triple(name, prompt, t)) }
                                saveButtons()
                                expandedType = false
                            }
                        )
                    }
                }
            }
            if (index < buttons.size - 1) {
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val scope = rememberCoroutineScope()

    val apiKey by settings.quickMoondreamAPIKey.collectAsState(initial = "")
    val captionLength by settings.quickCaptionLength.collectAsState(initial = QuickCaptionLength.SHORT.value)
    val captureInterval by settings.quickContinuousInterval.collectAsState(initial = QuickContinuousInterval._3S.value)
    val triggerMode by settings.quickTriggerMode.collectAsState(initial = Defaults.QUICK_TRIGGER_MODE)
    val controlStyle by settings.quickActionControlStyle.collectAsState(initial = com.eyepal.app.config.Defaults.QUICK_ACTION_CONTROL_STYLE)
    val savedPresetsJson by settings.quickPresets.collectAsState(initial = "")
    val translationEnabled by settings.quickTranslationEnabled.collectAsState(initial = false)
    val translationTarget by settings.quickTranslationTarget.collectAsState(initial = Defaults.TRANSLATION_TARGET)
    val quickModelProvider by settings.quickModelProvider.collectAsState(initial = Defaults.QUICK_MODEL_PROVIDER)
    val quickGemmaModelKind by settings.quickGemmaModelKind.collectAsState(initial = Defaults.QUICK_GEMMA_MODEL_KIND)
    val gemmaManager = remember { (context.applicationContext as EyePalApplication).container.gemmaModelManager }
    val gemmaStates by gemmaManager.states.collectAsState()

    val buttonTypes = listOf("Product", "Dish", "Short Text", "Custom")
    val quickButtons by remember(savedPresetsJson) {
        mutableStateOf(
            try {
                if (savedPresetsJson.isNotEmpty()) {
                    val arr = org.json.JSONArray(savedPresetsJson)
                    (0 until arr.length()).map { i ->
                        val obj = arr.getJSONObject(i)
                        Triple(obj.optString("name", ""), obj.optString("prompt", ""), obj.optString("type", "Custom"))
                    }.take(4)
                } else {
                    listOf(
                        Triple("Custom", "Tell me how many men and women there are and describe them; if not found, say No people found", "Custom"),
                        Triple("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function", "Product"),
                        Triple("Dish", "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms", "Dish"),
                        Triple("Short Text", "Describe the alphanumeric text visible in the image", "Short Text")
                    )
                }
            } catch (_: Exception) {
                listOf(
                    Triple("Custom", "Tell me how many men and women there are and describe them; if not found, say No people found", "Custom"),
                    Triple("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function", "Product"),
                    Triple("Dish", "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms", "Dish"),
                    Triple("Short Text", "Describe the alphanumeric text visible in the image", "Short Text")
                )
            }
        )
    }

    fun savePresets() {
        val arr = org.json.JSONArray()
        quickButtons.forEach { (name, prompt, type) ->
            arr.put(org.json.JSONObject().apply {
                put("name", name)
                put("prompt", prompt)
                put("type", type)
            })
        }
        scope.launch { settings.setQuickPresets(arr.toString()) }
    }

    val intervalOptions = QuickContinuousInterval.optionValues
    val intervalLabelRes = QuickContinuousInterval.optionLabelRes

    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        item {
            TopAppBar(title = { Text(stringResource(R.string.feature_quick_recognition)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
            Spacer(modifier = Modifier.height(16.dp))

            Text(stringResource(R.string.settings_model_provider), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            val providerOptions = listOf(Pair("gemma", R.string.settings_model_provider_gemma), Pair("moondream", R.string.settings_model_provider_moondream))
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                providerOptions.forEachIndexed { index, (value, labelRes) ->
                    SegmentedButton(selected = quickModelProvider == value, onClick = { scope.launch { settings.setQuickModelProvider(value) } }, shape = SegmentedButtonDefaults.itemShape(index, providerOptions.size)) { Text(stringResource(labelRes)) }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))

            if (quickModelProvider == "gemma") {
                Text(stringResource(R.string.gemma_section_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Spacer(modifier = Modifier.height(8.dp))
                GemmaModelKind.entries.forEach { kind ->
                    Spacer(modifier = Modifier.height(8.dp))
                    GemmaModelRow(
                        kind = kind,
                        state = gemmaStates[kind] ?: GemmaDownloadState.NotDownloaded,
                        manager = gemmaManager,
                        selected = GemmaModelKind.fromCode(quickGemmaModelKind) == kind,
                        onSelect = { scope.launch { settings.setQuickGemmaModelKind(kind.code) } }
                    )
                }
            }

            if (quickModelProvider == "moondream") {
                Text(stringResource(R.string.settings_moondream_api), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(value = apiKey, onValueChange = { scope.launch { settings.setQuickMoondreamAPIKey(it) } }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.label_api_key)) }, singleLine = true, visualTransformation = PasswordVisualTransformation())
            }
            Spacer(modifier = Modifier.height(24.dp))

            Spacer(modifier = Modifier.height(4.dp))
            Text(stringResource(R.string.settings_caption_length), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            var expandedCaption by remember { mutableStateOf(false) }
            val currentCaption = QuickCaptionLength.entries.find { it.value == captionLength } ?: QuickCaptionLength.SHORT
            ExposedDropdownMenuBox(expanded = expandedCaption, onExpandedChange = { expandedCaption = it }) {
                OutlinedTextField(
                    value = stringResource(currentCaption.labelRes),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.settings_caption_length)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedCaption) },
                    modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = expandedCaption, onDismissRequest = { expandedCaption = false }) {
                    QuickCaptionLength.entries.forEach { entry ->
                        DropdownMenuItem(text = { Text(stringResource(entry.labelRes)) }, onClick = {
                            scope.launch { settings.setQuickCaptionLength(entry.value) }
                            expandedCaption = false
                        })
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))

            Text(stringResource(R.string.settings_trigger_mode), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            val currentTriggerMode = QuickTriggerMode.fromValue(triggerMode)
            var expandedTriggerMode by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded = expandedTriggerMode, onExpandedChange = { expandedTriggerMode = it }) {
                OutlinedTextField(
                    value = stringResource(currentTriggerMode.labelRes),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.settings_trigger_mode)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedTriggerMode) },
                    modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = expandedTriggerMode, onDismissRequest = { expandedTriggerMode = false }) {
                    QuickTriggerMode.entries.forEach { entry ->
                        DropdownMenuItem(text = { Text(stringResource(entry.labelRes)) }, onClick = {
                            scope.launch { settings.setQuickTriggerMode(entry.value) }
                            expandedTriggerMode = false
                        })
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))

            Text(stringResource(R.string.settings_continuous_interval), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            val selectedIntervalRes = intervalLabelRes[intervalOptions.indexOf(captureInterval).coerceAtLeast(0)]
            var expandedInterval by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded = expandedInterval, onExpandedChange = { expandedInterval = it }) {
                OutlinedTextField(
                    value = stringResource(selectedIntervalRes),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.settings_continuous_interval)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedInterval) },
                    modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = expandedInterval, onDismissRequest = { expandedInterval = false }) {
                    intervalOptions.forEachIndexed { index, ms ->
                        DropdownMenuItem(text = { Text(stringResource(intervalLabelRes[index])) }, onClick = {
                            scope.launch { settings.setQuickContinuousInterval(ms) }
                            expandedInterval = false
                        })
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))

            Text(stringResource(R.string.settings_control_style), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            val currentControlStyle = RecognitionActionControlStyle.fromValue(controlStyle)
            var expandedControlStyle by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded = expandedControlStyle, onExpandedChange = { expandedControlStyle = it }) {
                OutlinedTextField(
                    value = stringResource(currentControlStyle.labelRes),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.settings_control_style)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedControlStyle) },
                    modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = expandedControlStyle, onDismissRequest = { expandedControlStyle = false }) {
                    RecognitionActionControlStyle.entries.forEach { entry ->
                        DropdownMenuItem(text = { Text(stringResource(entry.labelRes)) }, onClick = {
                            scope.launch { settings.setQuickActionControlStyle(entry.value) }
                            expandedControlStyle = false
                        })
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))

            Text(stringResource(R.string.settings_quick_buttons), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
        }

        items(quickButtons.size) { index ->
            val (name, prompt, type) = quickButtons[index]
            Text(stringResource(R.string.label_button, index + 1), style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(4.dp))
            OutlinedTextField(
                value = name,
                onValueChange = { newName ->
                    val updated = quickButtons.toMutableList().apply { set(index, Triple(newName, prompt, type)) }
                    val arr = org.json.JSONArray()
                    updated.forEach { (n, p, t) -> arr.put(org.json.JSONObject().apply { put("name", n); put("prompt", p); put("type", t) }) }
                    scope.launch { settings.setQuickPresets(arr.toString()) }
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.label_name)) },
                singleLine = true
            )
            Spacer(modifier = Modifier.height(4.dp))
            OutlinedTextField(
                value = prompt,
                onValueChange = { newPrompt ->
                    val updated = quickButtons.toMutableList().apply { set(index, Triple(name, newPrompt, type)) }
                    val arr = org.json.JSONArray()
                    updated.forEach { (n, p, t) -> arr.put(org.json.JSONObject().apply { put("name", n); put("prompt", p); put("type", t) }) }
                    scope.launch { settings.setQuickPresets(arr.toString()) }
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.label_prompt)) },
                maxLines = 3
            )
            Spacer(modifier = Modifier.height(4.dp))
            var expandedType by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { expandedType = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.label_type, type))
                }
                DropdownMenu(expanded = expandedType, onDismissRequest = { expandedType = false }) {
                    buttonTypes.forEach { t ->
                        DropdownMenuItem(
                            text = { Text(t) },
                            onClick = {
                                val updated = quickButtons.toMutableList().apply { set(index, Triple(name, prompt, t)) }
                                val arr = org.json.JSONArray()
                                updated.forEach { (n, p, tp) -> arr.put(org.json.JSONObject().apply { put("name", n); put("prompt", p); put("type", tp) }) }
                                scope.launch { settings.setQuickPresets(arr.toString()) }
                                expandedType = false
                            }
                        )
                    }
                }
            }
            if (index < quickButtons.size - 1) {
                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        item {
            Spacer(modifier = Modifier.height(24.dp))

            Text(stringResource(R.string.settings_translation), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(stringResource(R.string.settings_translation_enable), modifier = Modifier.weight(1f))
                Switch(checked = translationEnabled, onCheckedChange = { scope.launch { settings.setQuickTranslationEnabled(it) } })
            }
            Spacer(modifier = Modifier.height(8.dp))
            val currentLang = TranslationService.SUPPORTED_LANGUAGES.find { it.first == translationTarget }?.second ?: translationTarget
            var expandedTranslation by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded = expandedTranslation, onExpandedChange = { expandedTranslation = it }) {
                OutlinedTextField(
                    value = currentLang,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.target_language)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expandedTranslation) },
                    enabled = translationEnabled,
                    modifier = Modifier.menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable).fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = expandedTranslation, onDismissRequest = { expandedTranslation = false }) {
                    TranslationService.SUPPORTED_LANGUAGES.forEach { (code, name) ->
                        DropdownMenuItem(text = { Text(name) }, onClick = {
                            scope.launch { settings.setQuickTranslationTarget(code) }
                            expandedTranslation = false
                        })
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item { Spacer(modifier = Modifier.height(24.dp)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TextRecognitionSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val scope = rememberCoroutineScope()
    val textCooldown by settings.readTextSpeechCooldown.collectAsState(initial = Defaults.READ_TEXT_SPEECH_COOLDOWN)
    val ocrEngine by settings.ocrEngine.collectAsState(initial = Defaults.OCR_ENGINE)
    var ocrLogEntries by remember { mutableStateOf(OcrEngineLog.snapshot()) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState())) {
        TopAppBar(title = { Text(stringResource(R.string.settings_text_recognition)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
        Spacer(modifier = Modifier.height(16.dp))
        Text(stringResource(R.string.settings_ocr_engine), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(8.dp))
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            OcrEngine.entries.forEachIndexed { index, entry ->
                SegmentedButton(selected = ocrEngine == entry.value, onClick = { scope.launch { settings.setOcrEngine(entry.value) } }, shape = SegmentedButtonDefaults.itemShape(index, OcrEngine.entries.size)) { Text(stringResource(entry.labelRes)) }
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(stringResource(R.string.settings_features_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(4.dp))
        Spacer(modifier = Modifier.height(20.dp))
        Text(stringResource(R.string.settings_speech_cooldown_label, textCooldown.toInt()), style = MaterialTheme.typography.bodyMedium)
        Slider(
            value = textCooldown,
            onValueChange = { scope.launch { settings.setReadTextSpeechCooldown(it) } },
            valueRange = 1f..6f,
            steps = 4
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(stringResource(R.string.settings_ocr_log_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Spacer(modifier = Modifier.height(8.dp))
        Row {
            TextButton(
                onClick = {
                    val text = OcrEngineLog.copyAll()
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("OCR Log", text))
                },
                enabled = ocrLogEntries.isNotEmpty()
            ) { Text(stringResource(R.string.settings_copy_all_logs)) }
            TextButton(
                onClick = {
                    OcrEngineLog.clear()
                    ocrLogEntries = OcrEngineLog.snapshot()
                },
                enabled = ocrLogEntries.isNotEmpty()
            ) { Text(stringResource(R.string.clear_log), color = MaterialTheme.colorScheme.error) }
        }
        if (ocrLogEntries.isEmpty()) {
            Text(stringResource(R.string.settings_ocr_log_empty), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
        } else {
            Column {
                ocrLogEntries.takeLast(40).reversed().forEach { line ->
                    Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FacesSettingsScreen(onBack: () -> Unit, onNavigateToSavedFaces: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val scope = rememberCoroutineScope()
    val threshold by settings.faceMatchThreshold.collectAsState(initial = Defaults.FACE_MATCH_THRESHOLD)
    val margin by settings.faceMatchMargin.collectAsState(initial = Defaults.FACE_MATCH_MARGIN)
    val suggestUnknown by settings.suggestUnknownFaces.collectAsState(initial = Defaults.SUGGEST_UNKNOWN_FACES)
    val faceCooldown by settings.faceSpeechCooldown.collectAsState(initial = Defaults.FACE_SPEECH_COOLDOWN)

    val faceService = remember { (context.applicationContext as EyePalApplication).container.faceRecognitionService }
    val logEntries = remember { mutableStateOf<List<FaceRecognitionLogStore.LogEntry>>(emptyList()) }

    LaunchedEffect(Unit) {
        try {
            faceService.load()
        } catch (_: Exception) {}
        logEntries.value = faceService.logStore.getEntries()
    }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        item {
            TopAppBar(title = { Text(stringResource(R.string.tab_faces)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
            Spacer(modifier = Modifier.height(16.dp))
        }
        item {
            Text(stringResource(R.string.settings_speech), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.settings_speech_cooldown_label, faceCooldown.toInt()), style = MaterialTheme.typography.bodyMedium)
            Slider(
                value = faceCooldown,
                onValueChange = { scope.launch { settings.setFaceSpeechCooldown(it) } },
                valueRange = 1f..6f,
                steps = 4
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
        item {
            Text(stringResource(R.string.settings_recognition), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.settings_match_sensitivity_title), style = MaterialTheme.typography.bodyMedium)
            Text("${String.format(Locale.US, "%.0f", threshold * 100)}%", style = MaterialTheme.typography.bodyLarge)
            Slider(value = threshold, onValueChange = { scope.launch { settings.setFaceMatchThreshold(it) } }, valueRange = 0.30f..0.90f, steps = 59)
            Spacer(modifier = Modifier.height(12.dp))
            Text(stringResource(R.string.settings_top_match_margin_title), style = MaterialTheme.typography.bodyMedium)
            Text("${String.format(Locale.US, "%.3f", margin)}", style = MaterialTheme.typography.bodyLarge)
            Slider(value = margin, onValueChange = { scope.launch { settings.setFaceMatchMargin(it) } }, valueRange = 0.01f..0.10f, steps = 9)
            Spacer(modifier = Modifier.height(12.dp))
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(stringResource(R.string.settings_faces_suggest_unknown), modifier = Modifier.weight(1f))
                Switch(checked = suggestUnknown, onCheckedChange = { scope.launch { settings.setSuggestUnknownFaces(it) } })
            }
            Spacer(modifier = Modifier.height(24.dp))
        }
        item {
            Text(stringResource(R.string.settings_saved_faces), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = onNavigateToSavedFaces, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.tab_saved_faces)) }
            Spacer(modifier = Modifier.height(24.dp))
        }
        item {
            Text(stringResource(R.string.settings_recognition_log), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Spacer(modifier = Modifier.height(8.dp))
            Row {
                TextButton(
                    onClick = {
                        val text = faceService.logStore.copyAll()
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("Face Log", text))
                    },
                    enabled = logEntries.value.isNotEmpty()
                ) { Text(stringResource(R.string.settings_copy_all_logs)) }
                TextButton(
                    onClick = {
                        faceService.logStore.clear()
                        logEntries.value = faceService.logStore.getEntries()
                    },
                    enabled = logEntries.value.isNotEmpty()
                ) { Text(stringResource(R.string.clear_log), color = MaterialTheme.colorScheme.error) }
            }
            if (logEntries.value.isEmpty()) {
                Text(stringResource(R.string.label_no_events), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            } else {
                Column {
                    logEntries.value.takeLast(20).reversed().forEach { entry ->
                        val dateFormat = SimpleDateFormat("MMM dd HH:mm:ss", Locale.getDefault())
                        Text("[${dateFormat.format(Date(entry.timestamp))}] ${entry.message}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricPrompterSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val scope = rememberCoroutineScope()
    val provider by settings.lyricLLMProvider.collectAsState(initial = Defaults.LYRIC_LLM_PROVIDER)
    val modelID by settings.lyricModelID.collectAsState(initial = Defaults.MODEL_ID)
    val apiKey by settings.lyricAPIKey.collectAsState(initial = "")
    val baseUrl by settings.lyricBaseURL.collectAsState(initial = "")
    val advanceOffset by settings.lyricAdvanceOffset.collectAsState(initial = Defaults.LYRIC_ADVANCE_OFFSET)
    var availableModels by remember { mutableStateOf<List<String>>(emptyList()) }
    var isLoadingModels by remember { mutableStateOf(false) }
    var isCodexSignedIn by remember { mutableStateOf(OAuthService.isSignedIn(context)) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.settings_lyric_prompter)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
        Spacer(modifier = Modifier.height(16.dp))

        Text(stringResource(R.string.tab_playback), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Text(stringResource(R.string.label_advance_offset, String.format(Locale.US, "%.1f", advanceOffset)))
        Slider(value = advanceOffset, onValueChange = { scope.launch { settings.setLyricAdvanceOffset(it) } }, valueRange = 0f..5f, steps = 9)
        Spacer(modifier = Modifier.height(16.dp))

        Text(stringResource(R.string.tab_ai_provider), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            listOf("CODEX", "GEMINI", "OPENAI").forEachIndexed { index, name ->
                SegmentedButton(selected = provider == name, onClick = { scope.launch { settings.setLyricLLMProvider(name) } }, shape = SegmentedButtonDefaults.itemShape(index, 3)) { Text(name) }
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(value = modelID, onValueChange = { scope.launch { settings.setLyricModelID(it) } }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.label_model_id)) }, singleLine = true)
        if (provider == "CODEX") {
            Spacer(modifier = Modifier.height(8.dp))
            if (isCodexSignedIn) {
                Text(stringResource(R.string.label_signed_in), style = MaterialTheme.typography.bodyLarge, color = Color(0xFF4CAF50))
            } else {
                Text(stringResource(R.string.label_not_signed_in_hint), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.outline)
            }
        } else {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(value = apiKey, onValueChange = { scope.launch { settings.setLyricAPIKey(it) } }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.label_api_key)) }, singleLine = true)
        }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(value = baseUrl, onValueChange = { scope.launch { settings.setLyricBaseURL(it) } }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.label_base_url)) }, singleLine = true)
        Spacer(modifier = Modifier.height(12.dp))
        Button(
            onClick = {
                isLoadingModels = true
                scope.launch {
                    val models = withContext(Dispatchers.IO) {
                        try {
                            val client = OkHttpClient()
                            val baseUrl = when (provider) {
                                "OPENAI" -> "https://api.openai.com/v1"
                                "GEMINI" -> "https://generativelanguage.googleapis.com/v1beta"
                                else -> null
                            }
                            val token = when (provider) {
                                "OPENAI" -> apiKey
                                "GEMINI" -> apiKey
                                else -> ""
                            }
                            if (baseUrl.isNullOrEmpty() || token.isEmpty()) return@withContext emptyList()
                            val request = Request.Builder()
                                .url("$baseUrl/models")
                                .header("Authorization", "Bearer $token")
                                .get()
                                .build()
                            val response = client.newCall(request).execute()
                            val body = response.body?.string() ?: return@withContext emptyList()
                            val json = JSONObject(body)
                            val data = json.optJSONArray("data") ?: return@withContext emptyList()
                            (0 until data.length()).mapNotNull {
                                data.getJSONObject(it).optString("id")
                            }.sorted()
                        } catch (_: Exception) { emptyList() }
                    }
                    availableModels = models
                    isLoadingModels = false
                }
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isLoadingModels && apiKey.isNotBlank()
        ) {
            Text(if (isLoadingModels) stringResource(R.string.btn_loading) else stringResource(R.string.btn_refresh_models))
        }
        if (availableModels.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.label_available_models), style = MaterialTheme.typography.titleSmall)
            LazyColumn(modifier = Modifier.heightIn(max = 200.dp)) {
                items(availableModels) { model ->
                    ListItem(
                        headlineContent = { Text(model) },
                        trailingContent = {
                            if (model == modelID) {
                                Text(stringResource(R.string.label_selected), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
                            }
                        },
                        modifier = Modifier.clickable {
                            scope.launch { settings.setLyricModelID(model) }
                        }
                    )
                }
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(stringResource(R.string.tab_about), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
    }
}

@Composable
private fun GemmaModelRow(kind: GemmaModelKind, state: GemmaDownloadState, manager: GemmaModelManager, selected: Boolean, onSelect: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            RadioButton(selected = selected, onClick = onSelect)
            Spacer(modifier = Modifier.width(4.dp))
            Text(kind.displayName, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            when (state) {
                is GemmaDownloadState.Downloaded -> {
                    TextButton(onClick = { manager.delete(kind) }) { Text(stringResource(R.string.gemma_action_delete)) }
                }
                is GemmaDownloadState.Downloading -> {
                    TextButton(onClick = { manager.cancel(kind) }) { Text(stringResource(R.string.gemma_action_cancel)) }
                }
                GemmaDownloadState.NotDownloaded -> {
                    Button(onClick = { manager.download(kind) }) { Text(stringResource(R.string.gemma_action_download)) }
                }
                is GemmaDownloadState.Failed -> {
                    Button(onClick = { manager.download(kind) }) { Text(stringResource(R.string.gemma_action_retry)) }
                }
            }
        }
        when (state) {
            is GemmaDownloadState.Downloading -> {
                LinearProgressIndicator(
                    progress = { state.fraction.toFloat() },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    String.format(Locale.US, "%d%%", (state.fraction * 100).toInt()),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
            is GemmaDownloadState.Failed -> {
                Spacer(modifier = Modifier.height(4.dp))
                Text(state.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
            else -> {}
        }
    }
}
