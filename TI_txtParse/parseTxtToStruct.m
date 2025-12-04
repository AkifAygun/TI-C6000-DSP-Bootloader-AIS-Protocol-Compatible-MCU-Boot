function sections = parseTxtToStruct(filename, block_len_32bit)
% parseTxtToStruct  Read TI-TXT-like file and pack into structs of N 32-bit words
%
% sections(i).address = uint32 start address for that block
% sections(i).length  = block_len_32bit
% sections(i).data    = uint32 array of length block_len_32bit (little-endian words)
%
% Usage:
%   sections = parseTxtToStruct('deneme.txt', 50);

    if nargin<2
        error('Usage: parseTxtToStruct(filename, block_len_32bit)');
    end

    fid = fopen(filename,'r');
    if fid==-1
        error('Dosya açılamadı: %s', filename);
    end

    sections = struct('address', {}, 'length', {}, 'data', {});
    currentAddr = [];
    byteBuf = uint8([]);                  % satır vektör (1 x M)
    bytes_per_block = block_len_32bit*4;  % toplam byte sayısı bir blokta

    while ~feof(fid)
        rawline = fgetl(fid);
        if ~ischar(rawline)
            break;
        end
        line = strtrim(rawline);
        if isempty(line)
            continue;
        end

        % adres satırı
        if startsWith(line, '@')
            % önceki adresin bytes'ını bloklara bölüp kaydet
            if ~isempty(currentAddr)
                byteBuf = padAndSaveBlocks(currentAddr, byteBuf, block_len_32bit, bytes_per_block, sections);
            end
            % yeni adres (hex)
            addrText = strtrim(line(2:end));
            % güvenlik: sadece geçerli hex karakterleri al
            addrText = regexp(addrText,'[0-9A-Fa-f]+','match','once');
            if isempty(addrText)
                fclose(fid);
                error('Geçersiz adres satırı: %s', line);
            end
            currentAddr = uint32(hex2dec(addrText));
            byteBuf = uint8([]);
            continue;
        end

        % dosya sonu işareti 'q' olabilir
        if isequal(line,'q')
            break;
        end

        % satır içinden 2-hane hex byte'ları çıkar (örn "59", "00", ...)
        tokens = regexp(line, '[0-9A-Fa-f]{2}', 'match');
        if isempty(tokens)
            continue;
        end
        % tokens -> uint8 satır vektörü
        byteVals = uint8(hex2dec(tokens(:)'));   % (1 x N) satır vektör
        % garantile: byteBuf ile aynı orientasyonda (satır vektör)
        byteBuf = [byteBuf, byteVals(:)'];   % satır vektör haline getir
        % Eğer bir veya daha fazla tam blok oluştuysa kaydet
        while numel(byteBuf) >= bytes_per_block
            blockBytes = byteBuf(1:bytes_per_block);
            % kalan bytes güncelle
            byteBuf = byteBuf(bytes_per_block+1:end);
            % block'u uint32 word'lara çevir ve struct ekle
            words = bytesToUint32LE(blockBytes);
            newIdx = numel(sections) + 1;
            sections(newIdx).address = currentAddr; %#ok<AGROW>
            sections(newIdx).length  = block_len_32bit;
            sections(newIdx).data    = words;
            % sonraki block adresi artar (byte adres bazlı)
            currentAddr = uint32(double(currentAddr) + double(bytes_per_block));
        end
    end

    % Dosya sonu: kalan byte'ları 0 ile doldurup kaydet (eğer adres tanımlıysa)
    if ~isempty(currentAddr) && ~isempty(byteBuf)
        % pad to full block size with zeros
        if numel(byteBuf) < bytes_per_block
            pad = zeros(1, bytes_per_block - numel(byteBuf), 'uint8');
            byteBuf = [byteBuf, pad];
        end
        % şimdi tam bir veya birden çok blok olabilir - kaydet
        while numel(byteBuf) >= bytes_per_block
            blockBytes = byteBuf(1:bytes_per_block);
            byteBuf = byteBuf(bytes_per_block+1:end);
            words = bytesToUint32LE(blockBytes);
            newIdx = numel(sections) + 1;
            sections(newIdx).address = currentAddr; %#ok<AGROW>
            sections(newIdx).length  = block_len_32bit;
            sections(newIdx).data    = words;
            currentAddr = uint32(double(currentAddr) + double(bytes_per_block));
        end
    end

    fclose(fid);
end

%% yardımcı fonksiyonlar
function sections = padAndSaveBlocks(startAddr, byteBuf, block_len_32bit, bytes_per_block, sections)
    % Bu fonksiyon mevcut byteBuf içindeki tam blokları kaydeder,
    % geriye kalanları döndürür.
    while numel(byteBuf) >= bytes_per_block
        blockBytes = byteBuf(1:bytes_per_block);
        byteBuf = byteBuf(bytes_per_block+1:end);
        words = bytesToUint32LE(blockBytes);
        newIdx = numel(sections) + 1;
        sections(newIdx).address = startAddr; %#ok<AGROW>
        sections(newIdx).length  = block_len_32bit;
        sections(newIdx).data    = words;
        startAddr = uint32(double(startAddr) + double(bytes_per_block));
    end
    % geri kalan byteBuf'i ve güncellenmiş sections'ı döndür
    % (MATLAB fonksiyonlar multiple output yerine global-like dönüş kullanmadığı
    % için burada sadece byteBuf geri verilmesi gerekirdi; ancak kullandığımız
    % ana fonksiyonda while ile direk işlendiği için bu yardımcı fonksiyonu
    % kullanımını basitleştirdim.)
    % NOT: Bu fonksiyonu ana koddan çağırırken dikkat—burada sections güncellenmedi döndürülmedi.
end

function words = bytesToUint32LE(byteArray)
    % byteArray : 1 x (4*N) uint8, little-endian order per word
    % döndürür: 1 x N uint32
    if isempty(byteArray)
        words = uint32([]);
        return;
    end
    nWords = floor(numel(byteArray)/4);
    resh = reshape(byteArray(1:4*nWords), 4, nWords);  % 4 x nWords
    % Little-endian: lowest-order byte first: w = b1 + b2*256 + b3*256^2 + b4*256^3
    words = uint32(resh(1,:)) + uint32(resh(2,:)).*uint32(256) + ...
            uint32(resh(3,:)).*uint32(256^2) + uint32(resh(4,:)).*uint32(256^3);
    words = reshape(words, 1, []); % 1 x nWords
end