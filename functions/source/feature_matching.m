
function [ p1, p2 ] = feature_matching(img_file, para)

match_thr = para.match_thr;
im_rgb     =    double(imread(img_file));
[w,h,~]       = size(im_rgb);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
levels = 3;
min_octave = -1;
im = double(rgb2gray(uint8(im_rgb)));
im_smooth =  filter2(fspecial('average',3), im);
if para.sift_method ==1
    peak_Tresh = 0.1;
    [locs, descs] = vl_sift(single(im),'Levels',levels,'FirstOctave',min_octave,'Octaves', 5, 'PeakThresh',peak_Tresh,'EdgeThresh',12,'Max_keypoints',para.max_keypoints_octave ) ;
    feature_len = size(locs, 2);
    fprintf('found %d features\n', feature_len);
elseif para.sift_method == 2
    sift_bin = fullfile('lib','sift_win','siftfeat.exe');
    desc_file = 'temp_sift.txt';
    status1 = system([sift_bin ' ' img_file ' ' '-x' ' ' '-c' ' ' '0.05' ' ' '-o' ' ' desc_file ]);  %
    if status1 ~=0
        error('error calling executables');
    end
    [num, locs, descs] = import_sift(desc_file);
    locs = locs(:,[2,1,3,4]);
    locs = locs';
    locs = [locs; 100*ones(1, num)];
    descs = descs';
    delete(desc_file);
end

%%%%%%%%%%%%%%%%%%the min_sigma for each octave%%%%%%%%%%%%%%%%%%%%%
locs = locs';
locs = locs(:,[2,1,3,4]);
descs =double(descs');
sigmak = 2^(1/levels);
sigma_octave = sigmak^levels;
sigma0 = 1.6;
octaves_idx  = para.scale_seg;
octaves_sigma = sigma0*sigma_octave.^(octaves_idx);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
detected_sigmas = locs(:,3);
extend_octaves_sigma = [-inf,octaves_sigma(2:end),inf];
locs_scales    =  cell(1,length(octaves_idx));
descs_scales =  cell(1,length(octaves_idx));
octaves_num  =  length(octaves_idx);
for i = octaves_num:-1:1
    sigma_low = extend_octaves_sigma(i); sigma_high =  extend_octaves_sigma(i+1);
    locs_scales{octaves_num-i+1} = locs(sigma_low<=detected_sigmas & detected_sigmas<sigma_high, :);
    descs_scales{octaves_num-i+1} = descs(sigma_low<=detected_sigmas & detected_sigmas<sigma_high,:);
end

%%%%%%%%%%%%%%%%do matching%%%%%%%%%%%%%%%%%%%%%%%%%%%%
p1=[]; p2=[];
num = 0;

for i = 1:length(octaves_idx)
    cur_locs = locs_scales{i};
    cur_des =  descs_scales{i};
    if isempty(cur_locs)
        fprintf('no keypoints are detected in %dth octave\n', i);
        continue;
    end
    temp_locs = round(cur_locs(:,1:4));
    temp_locs(:,3:4) = cur_locs(:,3:4);
    
    %%%%%%%%%%%%%%gray level cluster%%%%%%%%%%%%%%%%%%%%%%
    cur_keys_n = size(temp_locs,1);
    gray_cls = 1;
    clusters = [];
    if cur_keys_n >=5000
        key_indx = (temp_locs(:,2)-1)*w + temp_locs(:,1);
        if cur_keys_n < 10000
            [clusters, ~] = gray_cluster(im_smooth, key_indx, 40,10, 5);
        else
            [clusters, ~] = gray_cluster(im_smooth, key_indx, 20,5, 5);
        end
        gray_cls = length(clusters);
    else
        clusters = {[1:cur_keys_n]};
    end
    
    for gray_indx = 1:gray_cls
        loc1 = temp_locs(clusters{gray_indx}, 1:4);
        des1 = cur_des(clusters{gray_indx},:);
        des1 = des1./repmat(sqrt(sum(des1.*des1,2)),1,size(des1,2));
        % sift matching
        des2t = des1';
        match_indx = [];
        if size(des1,1) > 1
            for i = 1 : size(des1,1)
                if ismember(i, match_indx)
                    continue;
                end
                dotprods = des1(i,:) * des2t;
                [vals,indx] = sort(acos(dotprods));
                
                j=2;
                if length(vals)>j&& vals(j)<match_thr* vals(j+1)
                    match_i = indx(j);
                    if  norm(loc1(i,:)-loc1(match_i,:),2)>para.min_clone_dis
                        num=num+1;
                        p1 = [p1; loc1(i,[2,1,3,4])];
                        p2 = [p2; loc1(match_i,[2,1,3,4])];
                        match_indx = [match_indx,i,match_i];
                    end
                end
            end
        end
    end
    if size(p1,1)==0
    else
        p    =  round([p1(:,1:2) p2(:,1:2)]);
        [p_temp, indx,~] =unique(p,'rows');
        p1=[p_temp(:,1:2), p1(indx,3:4)];
        p2=[p_temp(:,3:4), p2(indx,3:4)];
        num=size(p1,1);
    end
    %fprintf('Found %d matches.\n', num);
end

%%%%%%%%%remove isolated matching%%%%%%%%%%%%%%%%%
num = 0;
if ~isempty(p1)
    half_dis = para.min_clone_dis/2+para.half_dis_add;
    dis_map = pdist([p1(:,1:2); p2(:,1:2)]);
    dis_map_q = squareform(dis_map <= half_dis);
    neighbors = sum(dis_map_q);
    neighbors_p1 = neighbors(1:size(dis_map_q,2)/2);
    neighbors_p2 = neighbors(size(dis_map_q,2)/2+1: end);
    indx = neighbors_p1>=para.min_neighbors | neighbors_p2 >=para.min_neighbors;
    num = sum(indx);
    p1 = [p1(indx,1:2)'; ones(1,num) ; p1(indx,3:4)'];
    p2 = [p2(indx,1:2)'; ones(1,num) ; p2(indx,3:4)'];
end
fprintf('after remove the isoloated matching, found %d matches\n', num);
end
